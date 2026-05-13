# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "evaluation:improve rake task" do # rubocop:disable RSpec/DescribeClass
  let(:task_name) { "evaluation:improve" }
  let(:agent_name) { "Emails::ClassifyAgent" }
  let!(:prompt) { create(:orchestration_prompt, name: agent_name, system_prompt: "Classify emails.", user_prompt: "{{input}}") }
  let(:experiment) { create(:leva_experiment, prompt: prompt, status: :completed) }

  def stub_llm(system_prompt: "Improved prompt.", user_prompt: "{{input}}")
    body = {
      id: "cmpl-test", object: "chat.completion",
      model: "gpt-5.4",
      choices: [ { index: 0, message: { role: "assistant", content: JSON.generate({ "system_prompt" => system_prompt, "user_prompt" => user_prompt }) }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 200, completion_tokens: 80, total_tokens: 280 }
    }.to_json
    stub_request(:post, %r{api\.openai\.com})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  before do
    experiment
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[task_name].reenable
    stub_llm
  end

  context "when a completed experiment exists" do
    it "creates an improved Orchestration::Prompt" do
      expect { Rake::Task[task_name].invoke(agent_name) }
        .to change(Orchestration::Prompt, :count).by(1)
    end

    it "enqueues PromptAutoEvalJob for the new prompt" do
      Rake::Task[task_name].invoke(agent_name)
      new_prompt = Orchestration::Prompt.where(name: agent_name).order(id: :desc).first
      expect(Evaluation::PromptAutoEvalJob).to have_received(:perform_later).with(prompt_id: new_prompt.id).once
    end

    it "prints the new prompt version and id" do
      expect { Rake::Task[task_name].invoke(agent_name) }
        .to output(/Created improved prompt/).to_stdout
    end
  end

  context "when no completed experiment exists" do
    let(:experiment) { create(:leva_experiment, prompt: prompt, status: :pending) }

    it "raises ArgumentError" do
      expect { Rake::Task[task_name].invoke(agent_name) }
        .to raise_error(ArgumentError, /No completed experiment/)
    end
  end

  context "when agent_name is not provided" do
    it "raises ArgumentError" do
      expect { Rake::Task[task_name].invoke }
        .to raise_error(ArgumentError, /Usage/)
    end
  end
end
