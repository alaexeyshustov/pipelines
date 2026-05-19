# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::PromptImprover do
  let!(:experiment) { create(:evaluation_experiment, status: :completed) }
  let(:prompt) { experiment.prompt }

  def stub_improvement_agent(system_prompt: "Improved system", user_prompt: "Improved user")
    response_content = { "system_prompt" => system_prompt, "user_prompt" => user_prompt }
    agent_double = instance_double(Evaluation::Improvement::Agent)
    allow(agent_double).to receive_messages(with_model: agent_double, ask: double(content: response_content))
    allow(Evaluation::Improvement::Agent).to receive(:create).and_return(agent_double)
    agent_double
  end

  describe ".call" do
    it "raises ArgumentError when the experiment has no associated prompt" do
      experiment_without_prompt = create(:evaluation_experiment, prompt: nil)
      expect { described_class.call(experiment: experiment_without_prompt) }
        .to raise_error(ArgumentError, /no associated prompt/)
    end

    it "creates a new Prompt with the improved system prompt" do
      stub_improvement_agent(system_prompt: "Better instructions")
      expect { described_class.call(experiment: experiment) }
        .to change(Evaluation::Prompt, :count).by(1)
      expect(Evaluation::Prompt.last.system_prompt).to eq("Better instructions")
    end

    it "preserves the original prompt name" do
      stub_improvement_agent
      described_class.call(experiment: experiment)
      expect(Evaluation::Prompt.last.name).to eq(prompt.name)
    end

    it "falls back to the original user_prompt when the LLM returns an empty user_prompt" do
      stub_improvement_agent(user_prompt: "")
      described_class.call(experiment: experiment)
      expect(Evaluation::Prompt.last.user_prompt).to eq(prompt.user_prompt)
    end

    it "raises PromptImprover::Error when the LLM call fails" do
      allow(Evaluation::Improvement::Agent).to receive(:create).and_raise(StandardError, "network error")
      expect { described_class.call(experiment: experiment) }
        .to raise_error(Evaluation::PromptImprover::Error, /LLM call failed/)
    end

    it "raises PromptImprover::Error when the response is missing system_prompt" do
      agent_double = instance_double(Evaluation::Improvement::Agent)
      allow(agent_double).to receive_messages(with_model: agent_double, ask: double(content: { "user_prompt" => "ok" }))
      allow(Evaluation::Improvement::Agent).to receive(:create).and_return(agent_double)

      expect { described_class.call(experiment: experiment) }
        .to raise_error(Evaluation::PromptImprover::Error, /Missing system_prompt/)
    end

    it "raises PromptImprover::Error when the response content is invalid JSON string" do
      agent_double = instance_double(Evaluation::Improvement::Agent)
      allow(agent_double).to receive_messages(with_model: agent_double, ask: double(content: "not json"))
      allow(Evaluation::Improvement::Agent).to receive(:create).and_return(agent_double)

      expect { described_class.call(experiment: experiment) }
        .to raise_error(Evaluation::PromptImprover::Error)
    end
  end
end
