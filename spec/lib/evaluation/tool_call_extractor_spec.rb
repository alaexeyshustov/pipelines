# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ToolCallExtractor do
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
      tc = create(:tool_call, message: assistant_msg, name: "classify", arguments: { "label" => "offer" })
      create(:message, chat: chat, role: "tool", content: "done", parent_tool_call: tc)

      result = described_class.call(chat)
      expect(result.size).to eq(1)
      expect(result.first[:tool_name]).to eq("classify")
      expect(result.first[:result]).to eq("done")
    end

    it "skips tool messages without a parent tool call" do
      chat = create(:chat)
      create(:message, chat: chat, role: "tool", content: "orphan", parent_tool_call: nil)

      expect(described_class.call(chat)).to eq([])
    end

    it "returns multiple tool calls in order" do
      chat = create(:chat)
      assistant_msg = create(:message, chat: chat, role: "assistant", content: nil)
      tc1 = create(:tool_call, message: assistant_msg, name: "tool_a", arguments: {})
      tc2 = create(:tool_call, message: assistant_msg, name: "tool_b", arguments: {})
      create(:message, chat: chat, role: "tool", content: "a", parent_tool_call: tc1)
      create(:message, chat: chat, role: "tool", content: "b", parent_tool_call: tc2)

      result = described_class.call(chat)
      expect(result.map { |r| r[:tool_name] }).to eq(%w[tool_a tool_b])
    end
  end
end
