# Completed, chat-backed action runs of one agent: the rows Evaluation::DatasetSeeder turns into samples.
module CompletedAgentRuns
  def create_completed_agent_runs(agent_name, count)
    agent = create(:orchestration_agent, name: agent_name)
    action = create(:orchestration_action, kind: :agent, agent: agent)
    step_action = create(:orchestration_step_action, action: action)
    pipeline_run = create(:orchestration_pipeline_run, pipeline: step_action.step.pipeline)
    Array.new(count) do
      create(:orchestration_action_run, step_action:, pipeline_run:, status: "completed", chat: create(:chat),
                                        input: { "emails" => [ { "id" => "1" } ] })
    end
  end
end

RSpec.configure { |config| config.include CompletedAgentRuns }
