module Evaluation
  class ToolCallExtractor
    def self.call(chat)
      return [] if chat.nil?

      # steep:ignore:start
      messages = if chat.messages.loaded?
        chat.messages.select { |m| m.role == "tool" }.sort_by(&:id)
      else
        chat.messages.includes(:parent_tool_call).where(role: "tool").order(:id)
      end

      messages.filter_map do |msg|
        tc = msg.parent_tool_call
        tc && { tool_name: tc.name, arguments: tc.arguments, result: msg.content }
      end
      # steep:ignore:end
    end
  end
end
