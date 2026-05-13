require "rails_helper"

RSpec.describe Evaluation::PromptImprover do
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:prompt) { create(:orchestration_prompt, name: agent_name, system_prompt: "You classify emails.", user_prompt: "{{input}}") }
  let!(:experiment) { create(:leva_experiment, prompt: prompt, status: :completed) }

  def stub_llm(system_prompt: "Improved system.", user_prompt: "{{input}}")
    body = {
      id: "cmpl-test", object: "chat.completion",
      model: "gpt-5.4",
      choices: [ { index: 0, message: { role: "assistant", content: JSON.generate({ "system_prompt" => system_prompt, "user_prompt" => user_prompt }) }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 200, completion_tokens: 80, total_tokens: 280 }
    }.to_json
    stub_request(:post, %r{api\.openai\.com})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  def make_eval_result(score:, metric_name:, justification: "Good job.")
    runner_result = create(:leva_runner_result, experiment: experiment)
    eval_result = create(:leva_evaluation_result,
      experiment: experiment,
      runner_result: runner_result,
      dataset_record: runner_result.dataset_record,
      score: score)
    create(:evaluation_justification, evaluation_result: eval_result, metric_name: metric_name, justification: justification)
    eval_result
  end

  before do
    create(:evaluation_metric, agent_name: agent_name, name: "accuracy", description: "How accurate is it?")
    stub_llm
  end

  describe ".call" do
    it "enqueues PromptAutoEvalJob for the new prompt" do
      result = described_class.call(experiment: experiment)
      expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: result.id).once
    end

    it "returns a new Orchestration::Prompt" do
      result = described_class.call(experiment: experiment)
      expect(result).to be_a(Orchestration::Prompt)
      expect(result).to be_persisted
    end

    it "creates a prompt with the same agent name" do
      result = described_class.call(experiment: experiment)
      expect(result.name).to eq(agent_name)
    end

    it "creates a new prompt record (does not mutate original)" do
      expect { described_class.call(experiment: experiment) }.to change(Orchestration::Prompt, :count).by(1)
    end

    it "uses the improved system prompt from LLM" do
      stub_llm(system_prompt: "Better classification prompt.")
      result = described_class.call(experiment: experiment)
      expect(result.system_prompt).to eq("Better classification prompt.")
    end

    it "uses the improved user prompt from LLM" do
      stub_llm(user_prompt: "Improved {{input}}")
      result = described_class.call(experiment: experiment)
      expect(result.user_prompt).to eq("Improved {{input}}")
    end

    it "includes the current system prompt in the LLM request" do
      described_class.call(experiment: experiment)
      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        req.body.include?("You classify emails.")
      }
    end

    it "includes evaluation scores and justifications in the LLM request" do
      make_eval_result(score: 2.0, metric_name: "accuracy", justification: "Missed several emails.")
      described_class.call(experiment: experiment)
      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        req.body.include?("accuracy") && req.body.include?("Missed several emails.")
      }
    end

    it "includes metric rubrics in the LLM request" do
      described_class.call(experiment: experiment)
      expect(WebMock).to have_requested(:post, %r{api\.openai\.com}).with { |req|
        req.body.include?("How accurate is it?")
      }
    end

    context "when experiment has no associated prompt" do
      let(:experiment) { create(:leva_experiment, prompt: nil, status: :completed) }

      it "raises ArgumentError" do
        expect { described_class.call(experiment: experiment) }
          .to raise_error(ArgumentError, /no.*prompt/i)
      end
    end

    context "when LLM returns invalid JSON" do
      before do
        body = {
          id: "cmpl-test", object: "chat.completion",
          model: "gpt-5.4",
          choices: [ { index: 0, message: { role: "assistant", content: "not json" }, finish_reason: "stop" } ],
          usage: { prompt_tokens: 100, completion_tokens: 10, total_tokens: 110 }
        }.to_json
        stub_request(:post, %r{api\.openai\.com})
          .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
      end

      it "raises PromptImprover::Error" do
        expect { described_class.call(experiment: experiment) }
          .to raise_error(Evaluation::PromptImprover::Error, /invalid json/i)
      end
    end
  end
end
