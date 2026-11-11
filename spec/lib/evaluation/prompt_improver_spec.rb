require "rails_helper"

RSpec.describe Evaluation::PromptImprover do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:prompt) { create(:orchestration_prompt, name: agent_name, system_prompt: "You classify emails.", user_prompt: "{{input}}") }
  let!(:experiment) { create(:evaluation_experiment, prompt: prompt, status: :completed) }
  let(:content) { JSON.generate({ system_prompt: "Improved system.", user_prompt: "{{input}}" }) }

  def stub_llm(content: self.content, status: 200, model: "gpt-5.4")
    body = if status == 200
      { id: "cmpl-test", object: "chat.completion", model: model,
        choices: [ { index: 0, message: { role: "assistant", content: content }, finish_reason: "stop" } ],
        usage: { prompt_tokens: 200, completion_tokens: 80, total_tokens: 280 } }
    else
      { error: { message: "boom", type: "server_error" } }
    end
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def make_eval_result(score:, metric_name:, justification:, **attrs)
    dataset_sample = create(:evaluation_dataset_sample, dataset: experiment.dataset)
    sample = create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample)
    result = create(:evaluation_evaluation_result, experiment: experiment, sample: sample,
                                                   dataset_sample: dataset_sample, score: score, **attrs)
    create(:evaluation_justification, evaluation_result: result, metric_name: metric_name, justification: justification)
  end

  before do
    create(:evaluation_metric, agent_name: agent_name, name: "accuracy", description: "How accurate is it?")
    stub_request(:post, %r{api\.openai\.com}).to_return(stub_llm)
  end

  describe ".call" do
    it "creates a new version of the prompt with the improved texts and enqueues its auto evaluation" do
      stub_request(:post, %r{api\.openai\.com}).to_return(stub_llm(content: JSON.generate({ system_prompt: "Better.", user_prompt: "Improved {{input}}" })))
      result = nil
      expect { result = described_class.call(experiment: experiment) }.to change(Evaluation::Prompt, :count).by(1)

      expect(result).to have_attributes(name: agent_name, version: prompt.version + 1,
                                        system_prompt: "Better.", user_prompt: "Improved {{input}}")
      expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: result.id).once
    end

    it "keeps the original user_prompt when the LLM returns an empty one" do
      stub_request(:post, %r{api\.openai\.com}).to_return(stub_llm(content: JSON.generate({ system_prompt: "Better.", user_prompt: "" })))
      expect(described_class.call(experiment: experiment).user_prompt).to eq(prompt.user_prompt)
    end

    it "preserves the output_schema of the current prompt" do
      schema = { "type" => "object", "properties" => { "label" => { "type" => "string" } } }
      prompt.update!(output_schema: schema)
      expect(described_class.call(experiment: experiment).output_schema).to eq(schema)
    end

    it "sends the prompt, metric levels and the derived justification with normalized score to the LLM" do
      Evaluation::Metric.find_by!(name: "accuracy").update!(kind: "score", levels: [ "wrong", "partly right", "right" ])
      make_eval_result(score: 0.6, metric_name: "accuracy", passed: false, confidence: 0.8, justification: "partly right [confidence 0.8]")
      described_class.call(experiment: experiment)

      expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
        user = JSON.parse(req.body)["messages"].find { |m| m["role"] == "user" }["content"]
        data = JSON.parse(user[/\{.*\}/m])
        data["metrics"].first.values_at("kind", "levels") == [ "score", [ "wrong", "partly right", "right" ] ] &&
          data["scores"].first.slice("score", "passed", "confidence").values == [ 0.6, false, 0.8 ] &&
          data["scores"].first["justification"].include?("partly right [confidence 0.8]")
      })
    end

    it "appends the agent output schema to the user message" do
      create(:orchestration_agent, name: agent_name,
             output_schema: { "type" => "object", "properties" => { "results" => { "type" => "array" } } })
      described_class.call(experiment: experiment)
      expect(WebMock).to(have_requested(:post, %r{api\.openai\.com}).with { |req|
        user = JSON.parse(req.body)["messages"].find { |m| m["role"] == "user" }["content"]
        user.include?("<output_schema>") && user.include?("\"results\"")
      })
    end

    it "attributes the LLM usage to the experiment" do
      described_class.call(experiment: experiment)
      expect(RubyLLM::ActiveRecord::Usage.where(owner: experiment).count).to be >= 1
    end

    it "falls back to the next model when the primary provider fails" do
      stub_request(:post, %r{api\.openai\.com}).to_return(stub_llm(status: 500))
      stub_request(:post, %r{api\.mistral\.ai}).to_return(stub_llm(model: "mistral-large-latest"))

      expect(described_class.call(experiment: experiment).system_prompt).to eq("Improved system.")
      expect(WebMock).to have_requested(:post, %r{api\.mistral\.ai})
    end

    it "raises ArgumentError when the experiment has no associated prompt" do
      expect { described_class.call(experiment: create(:evaluation_experiment, prompt: nil)) }
        .to raise_error(ArgumentError, /no associated prompt/)
    end

    it "raises Error when the response is not valid JSON" do
      stub_request(:post, %r{api\.openai\.com}).to_return(stub_llm(content: "not json"))
      expect { described_class.call(experiment: experiment) }
        .to raise_error(Evaluation::PromptImprover::Error, /invalid output/)
    end

    it "raises Error when system_prompt is missing" do
      stub_request(:post, %r{api\.openai\.com}).to_return(stub_llm(content: JSON.generate({ user_prompt: "ok" })))
      expect { described_class.call(experiment: experiment) }
        .to raise_error(Evaluation::PromptImprover::Error, /Missing system_prompt/)
    end

    it "raises Error when every model fails" do
      stub_request(:post, %r{api\.(openai|mistral)}).to_return(stub_llm(status: 401))
      expect { described_class.call(experiment: experiment) }
        .to raise_error(Evaluation::PromptImprover::Error, /LLM call failed/)
    end
  end
end
