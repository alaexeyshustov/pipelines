# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ToolCallExtractor do
  def create_tool_call(message, name:, arguments: {})
    message.ruby_llm_tool_calls.create!(tool_call_id: SecureRandom.uuid, name: name, arguments: arguments)
  end

  def create_tool_result(chat, tool_call, content)
    create(:message, chat: chat, role: "tool", content: content).tap { |msg| tool_call.update!(result: msg) }
  end

  describe ".call" do
    it "returns an empty array when chat is nil" do
      expect(described_class.call(nil)).to eq([])
    end

    it "returns an empty array when chat has no tool messages" do
      chat = create(:chat)
      create(:message, chat: chat, role: "assistant", content: "hello")
      expect(described_class.call(chat)).to eq([])
    end

    it "returns tool call data for each tool message that has a parent tool call" do
      chat = create(:chat)
      assistant_msg = create(:message, chat: chat, role: "assistant", content: nil)
      tc = create_tool_call(assistant_msg, name: "classify", arguments: { "label" => "offer" })
      create_tool_result(chat, tc, "done")

      result = described_class.call(chat)
      expect(result.size).to eq(1)
      expect(result.first["tool_name"]).to eq("classify")
      expect(result.first["result"]).to eq("done")
    end

    it "skips tool messages without a parent tool call" do
      chat = create(:chat)
      create(:message, chat: chat, role: "tool", content: "orphan")

      expect(described_class.call(chat)).to eq([])
    end

    it "returns multiple tool calls in order" do
      chat = create(:chat)
      assistant_msg = create(:message, chat: chat, role: "assistant", content: nil)
      tc1 = create_tool_call(assistant_msg, name: "tool_a")
      tc2 = create_tool_call(assistant_msg, name: "tool_b")
      create_tool_result(chat, tc1, "a")
      create_tool_result(chat, tc2, "b")

      result = described_class.call(chat)
      expect(result.pluck("tool_name")).to eq(%w[tool_a tool_b])
    end
  end
end
