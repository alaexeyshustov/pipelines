require 'rails_helper'
require 'rake'

RSpec.describe "evaluation:migrate_prompts rake task" do # rubocop:disable RSpec/DescribeClass
  let(:task_name) { "evaluation:migrate_prompts" }
  let(:agent_classes) do
    %w[
      Emails::ClassifyAgent
      Emails::FilterAgent
      Emails::MappingAgent
      Records::FillAgent
      Records::NormalizeAgent
      Records::StoreAgent
      Records::ReconcileAgent
    ]
  end

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[task_name].reenable
  end

  it "creates one Leva::Prompt per agent class" do
    expect { Rake::Task[task_name].invoke }
      .to change(Leva::Prompt, :count).by(agent_classes.size)
  end

  it "creates prompts named after each agent class" do
    Rake::Task[task_name].invoke
    created_names = Leva::Prompt.pluck(:name)
    expect(created_names).to match_array(agent_classes)
  end

  it "sets system_prompt from the agent's inline instructions" do
    Rake::Task[task_name].invoke
    aggregate_failures do
      agent_classes.each do |agent_class|
        prompt = Leva::Prompt.find_by!(name: agent_class)
        expected = agent_class.constantize.instructions
        expect(prompt.system_prompt).to eq(expected)
      end
    end
  end

  it "is idempotent (running twice does not create duplicates)" do
    Rake::Task[task_name].invoke
    Rake::Task[task_name].reenable
    expect { Rake::Task[task_name].invoke }
      .not_to change(Leva::Prompt, :count)
  end

  it "updates system_prompt if instructions changed on re-run" do
    Rake::Task[task_name].invoke
    original = Leva::Prompt.find_by!(name: "Emails::ClassifyAgent")
    original.update!(system_prompt: "old instructions")

    Rake::Task[task_name].reenable
    Rake::Task[task_name].invoke

    expect(original.reload.system_prompt).to eq(Emails::ClassifyAgent.instructions)
  end
end
