# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "evaluation:seed_dataset" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["evaluation:seed_dataset"] }
  let(:agent_name) { "Emails::ClassifyAgent" }
  let(:orchestration_agent) { create(:orchestration_agent, name: agent_name) }
  let(:step_action) do
    action = create(:orchestration_action, kind: :agent, agent: orchestration_agent)
    create(:orchestration_step_action, action: action)
  end
  let(:pipeline_run) { create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline) }

  before do
    Rails.application.load_tasks if Rake::Task.task_defined?("evaluation:seed_dataset") == false
    task.reenable
  end

  def create_completed_action_run(chat: nil)
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: "completed",
           chat: chat,
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] })
  end

  context "when completed action runs with chats exist" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:chat) { create(:chat) }
    let(:action_run) { create_completed_action_run(chat: chat) }

    before { action_run }

    it "creates a dataset named after the agent" do
      task.invoke(agent_name, "1")

      expect(Leva::Dataset.find_by(name: agent_name)).to be_present
    end

    it "creates dataset records for each sampled action run" do
      task.invoke(agent_name, "1")

      dataset = Leva::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_records.count).to eq(1)
    end

    it "links the dataset record to the action run as recordable" do
      task.invoke(agent_name, "1")

      dataset = Leva::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_records.first.recordable).to eq(action_run)
    end
  end

  context "when run twice" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:chat) { create(:chat) }
    let(:action_run) { create_completed_action_run(chat: chat) }

    before { action_run }

    it "does not duplicate dataset records" do
      task.invoke(agent_name, "1")
      task.reenable
      task.invoke(agent_name, "1")

      dataset = Leva::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_records.count).to eq(1)
    end

    it "does not duplicate the dataset" do
      task.invoke(agent_name, "1")
      task.reenable
      task.invoke(agent_name, "1")

      expect(Leva::Dataset.where(name: agent_name).count).to eq(1)
    end
  end

  context "when no completed action runs exist" do
    it "does not create a dataset" do
      task.invoke(agent_name, "10")

      expect(Leva::Dataset.find_by(name: agent_name)).to be_nil
    end
  end
end
