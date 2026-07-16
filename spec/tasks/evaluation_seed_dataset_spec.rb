# rubocop:disable RSpec/DescribeClass

require "rails_helper"
require "rake"

RSpec.describe "evaluation:seed_dataset" do
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
    allow(Evaluation::ToolCallExtractor).to receive(:call).and_return([])
  end

  def create_completed_action_run(chat: nil)
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: "completed",
           chat: chat,
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] })
  end

  context "when completed action runs with chats exist" do
    let(:chat) { create(:chat) }
    let(:action_run) { create_completed_action_run(chat: chat) }

    before { action_run }

    it "creates a dataset named after the agent" do
      task.invoke(agent_name, "1")

      expect(Evaluation::Dataset.find_by(name: agent_name)).to be_present
    end

    it "creates dataset samples for each sampled action run" do
      task.invoke(agent_name, "1")

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(1)
    end

    it "stores the action run input in the dataset sample" do
      task.invoke(agent_name, "1")

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.first.input).to eq(action_run.input)
    end
  end

  context "when run twice" do
    let(:chat) { create(:chat) }
    let(:action_run) { create_completed_action_run(chat: chat) }

    before { action_run }

    it "does not duplicate dataset samples" do
      task.invoke(agent_name, "1")
      task.reenable
      task.invoke(agent_name, "1")

      dataset = Evaluation::Dataset.find_by!(name: agent_name)
      expect(dataset.dataset_samples.count).to eq(1)
    end

    it "does not duplicate the dataset" do
      task.invoke(agent_name, "1")
      task.reenable
      task.invoke(agent_name, "1")

      expect(Evaluation::Dataset.where(name: agent_name).count).to eq(1)
    end
  end

  context "when no completed action runs exist" do
    before { create(:orchestration_agent, name: agent_name) }

    it "creates an empty dataset" do
      task.invoke(agent_name, "10")

      dataset = Evaluation::Dataset.find_by(name: agent_name)
      expect(dataset).to be_present
      expect(dataset.dataset_samples.count).to eq(0)
    end
  end

  context "when the agent name is unknown" do
    it "raises ArgumentError" do
      expect { task.invoke("Unknown::Agent", "10") }.to raise_error(ArgumentError, /Unknown agent/)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
 