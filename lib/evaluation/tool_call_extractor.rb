module Evaluation
  class ToolCallExtractor
    def self.call(chat)
      return [] if chat.nil?

      rel = chat.messages.where(role: "tool") # : ActiveRecord::Relation
      ordered = rel.order(:id) # : ActiveRecord::Relation
      incl = ordered.includes(:parent_tool_call) # : ActiveRecord::Relation
      messages = incl.to_a # : Array[Message]
      messages.filter_map do |msg|
        tc = msg.parent_tool_call
        next unless tc

        {
          "tool_name" => tc.name,
          "arguments" => tc.arguments,
          "result" => msg.content.to_s
        }
      end
    end
  end
end
