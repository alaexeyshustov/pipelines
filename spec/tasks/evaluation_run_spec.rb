# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "evaluation:run rake task" do # rubocop:disable RSpec/DescribeClass
  let(:task_name) { "evaluation:run" }
  let(:agent_name) { "Emails::ClassifyAgent" }
  let!(:prompt)  { create(:orchestration_prompt, name: agent_name, version: 1) }
  let!(:dataset) { create(:evaluation_dataset, name: agent_name) }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[task_name].reenable
  end

  context "when agent_name, prompt, and dataset exist" do
    it "creates a Evaluation::Experiment" do
      expect { Rake::Task[task_name].invoke(agent_name, nil) }
        .to change(Evaluation::Experiment, :count).by(1)
    end

    it "sets runner_class to Evaluation::Runners::StubbedAgentRun" do
      Rake::Task[task_name].invoke(agent_name, nil)
      expect(Evaluation::Experiment.last.runner_class).to eq("Evaluation::Runners::StubbedAgentRun")
    end

    it "sets evaluator_classes to Evaluation::Evaluators::LLMJudgeEval" do
      Rake::Task[task_name].invoke(agent_name, nil)
      expect(Evaluation::Experiment.last.evaluator_classes).to eq([ "Evaluation::Evaluators::LLMJudgeEval" ])
    end

    it "links the experiment to the active prompt" do
      Rake::Task[task_name].invoke(agent_name, nil)
      expect(Evaluation::Experiment.last.prompt_id).to eq(prompt.id)
    end

    it "links the experiment to the agent dataset" do
      Rake::Task[task_name].invoke(agent_name, nil)
      expect(Evaluation::Experiment.last.dataset).to eq(dataset)
    end

    it "enqueues Evaluation::ExperimentJob" do
      allow(Evaluation::ExperimentJob).to receive(:perform_later)
      Rake::Task[task_name].invoke(agent_name, nil)
      expect(Evaluation::ExperimentJob).to have_received(:perform_later).once
    end

    it "prints the experiment id" do
      expect { Rake::Task[task_name].invoke(agent_name, nil) }
        .to output(/#\d+/).to_stdout
    end

    context "when multiple prompt versions exist" do
      let!(:newer_prompt) { create(:orchestration_prompt, name: agent_name, version: 2) }

      it "uses the highest version" do
        Rake::Task[task_name].invoke(agent_name, nil)
        expect(Evaluation::Experiment.last.prompt_id).to eq(newer_prompt.id)
      end
    end

    context "when two prompts share the same version" do
      let!(:second_prompt) { create(:orchestration_prompt, name: agent_name, version: 1) }

      it "uses the highest id as a tiebreaker" do
        Rake::Task[task_name].invoke(agent_name, nil)
        expect(Evaluation::Experiment.last.prompt_id).to eq(second_prompt.id)
      end
    end
  end

  context "when model argument is provided" do
    let(:model) { "mistral-large-latest" }

    it "stores the model in experiment metadata" do
      Rake::Task[task_name].invoke(agent_name, model)
      expect(Evaluation::Experiment.last.metadata).to include("pipeline_model" => model)
    end

    it "includes the model in the experiment name" do
      Rake::Task[task_name].invoke(agent_name, model)
      expect(Evaluation::Experiment.last.name).to include(model)
    end
  end

  context "when agent_name is missing" do
    it "raises ArgumentError with usage message" do
      expect { Rake::Task[task_name].invoke(nil, nil) }
        .to raise_error(ArgumentError, /Usage/)
    end
  end

  context "when no prompt exists for the agent" do
    let!(:prompt) { nil }

    it "raises ArgumentError mentioning the agent" do
      expect { Rake::Task[task_name].invoke(agent_name, nil) }
        .to raise_error(ArgumentError, /#{agent_name}/)
    end
  end

  context "when no dataset exists for the agent" do
    let!(:dataset) { nil }

    it "raises ActiveRecord::RecordNotFound" do
      expect { Rake::Task[task_name].invoke(agent_name, nil) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
