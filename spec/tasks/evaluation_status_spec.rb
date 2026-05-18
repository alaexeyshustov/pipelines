# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "evaluation:status rake task" do # rubocop:disable RSpec/DescribeClass
  let(:task_name) { "evaluation:status" }
  let(:agent_name) { "Emails::ClassifyAgent" }

  let!(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
  let!(:prompt) { create(:orchestration_prompt, name: agent_name) }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[task_name].reenable
  end

  def run_task
    output = StringIO.new
    $stdout = output
    Rake::Task[task_name].invoke
    output.string
  ensure
    $stdout = STDOUT
  end

  it "prints a header row" do
    output = run_task
    expect(output).to match(/Agent/i)
    expect(output).to match(/Samples/i)
  end

  it "prints a row for the agent" do
    output = run_task
    expect(output).to include(agent_name)
  end

  it "shows the active prompt version" do
    output = run_task
    expect(output).to match(/v\d+/)
  end

  context "when no experiment exists" do
    it "shows n/a for experiment id" do
      output = run_task
      expect(output).to match(/#{Regexp.escape(agent_name)}.*n\/a/)
    end

    it "shows n/a for score" do
      output = run_task
      expect(output).to match(/n\/a/)
    end
  end

  context "when an experiment with results exists" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:dataset) { create(:evaluation_dataset, name: agent_name) }
    let(:experiment) do
      create(:evaluation_experiment,
             prompt: prompt,
             dataset: dataset,
             status: :completed)
    end
    let(:runner_result) { create(:evaluation_runner_result, experiment: experiment) }

    before do
      create(:evaluation_evaluation_result,
             experiment: experiment,
             runner_result: runner_result,
             dataset_record: runner_result.dataset_record,
             score: 4.0)
      create(:evaluation_evaluation_result,
             experiment: experiment,
             runner_result: runner_result,
             dataset_record: runner_result.dataset_record,
             score: 2.0)
    end

    it "shows the experiment id" do
      output = run_task
      expect(output).to include("##{experiment.id}")
    end

    it "shows the average score" do
      output = run_task
      expect(output).to include("3.00")
    end
  end

  context "when qualifying action runs exist" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:action) { create(:orchestration_action, kind: :agent, agent: orchestration_agent) }
    let(:step_action) { create(:orchestration_step_action, action: action) }
    let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }

    before do
      chat = create(:chat)
      create(:orchestration_action_run,
             step_action: step_action,
             pipeline_run: pipeline_run,
             status: "completed",
             chat: chat)
    end

    it "shows the qualifying sample count" do
      output = run_task
      expect(output).to match(/#{Regexp.escape(agent_name)}\s+1\b/)
    end
  end
end
