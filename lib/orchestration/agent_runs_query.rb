module Orchestration
  module AgentRunsQuery
    Run = Data.define(:id, :input, :chat)
    # `chat` is a LIVE chat handle by design (consumed downstream by the
    # evaluation module's tool-call extraction), not a serialized value — an
    # intentional exception to "DTOs never carry live/AR objects". `id`/`input`
    # are plain values.

    def self.completed_with_chat(agent_name:, limit:)
      Orchestration::ActionRun
        .joins(step_action: { action: :agent })
        .where(status: "completed")
        .where.not(chat_id: nil)
        .where(orchestration_agents: { name: agent_name })
        .order(id: :desc)
        .limit(limit)
        .map { |run| Run.new(id: run.id, input: run.input, chat: run.chat) }
    end
  end
end
