require "rails_helper"
require "rake"

# Seeding behaviour is specified in spec/lib/evaluation/dataset_seeder_spec.rb; this only covers the task wiring.
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
    allow(Evaluation::ToolCallExtractor).to receive(:call).and_return([])
  end

  def create_completed_action_run
    create(:orchestration_action_run,
           step_action: step_action,
           pipeline_run: pipeline_run,
           status: "completed",
           chat: create(:chat),
           input: { "emails" => [ { "id" => "1", "subject" => "Job offer" } ] })
  end

  it "seeds the agent's dataset with up to sample_size action runs" do
    2.times { create_completed_action_run }

    expect { task.invoke(agent_name, "1") }.to output("Dataset '#{agent_name}': 1 created, 0 skipped.\n").to_stdout

    expect(Evaluation::Dataset.find_by!(name: agent_name).dataset_samples.count).to eq(1)
  end

  context "when the agent name is unknown" do
    it "raises ArgumentError" do
      expect { task.invoke("Unknown::Agent", "10") }.to raise_error(ArgumentError, /Unknown agent/)
    end
  end
end
