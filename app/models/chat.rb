class Chat < ApplicationRecord
  include Leva::Recordable

  acts_as_chat

  has_many :action_runs, class_name: "Orchestration::ActionRun", dependent: :nullify

  def index_attributes
    {
      id: id,
      messages_count: messages.count,
      created_at: created_at
    }
  end

  def show_attributes
    {
      id: id,
      model: model&.name,
      messages_count: messages.count,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def to_llm_context
    {
      messages: messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")
    }
  end

  def ground_truth
    nil
  end
end
