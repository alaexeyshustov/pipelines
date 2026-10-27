# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chats::MessageComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:tool_calls) { {} }
  let(:tokens) { RubyLLM::Tokens.new(input: 0, output: 0, cache_read: 0) }
  let(:message) do
    build_stubbed(:message,
                  role: "user",
                  content: "Hello, world!",
                  thinking_text: nil,
                  created_at: Time.zone.parse("2026-04-08 10:00:00"))
  end
  let(:component) { described_class.new(message: message) }

  before do
    allow(message).to receive_messages(tool_calls: tool_calls, tokens: tokens)
  end

  it "renders the message wrapper" do
    expect(rendered.css("[data-testid='chat-message']")).to be_present
  end

  it "renders the role badge" do
    expect(rendered.css("[data-testid='message-role']").text.strip).to eq("user")
  end

  it "renders the message content" do
    expect(rendered.text).to include("Hello, world!")
  end

  it "renders the formatted time" do
    expect(rendered.text).to include("10:00:00")
  end

  it "does not render the thinking section when absent" do
    expect(rendered.css("details")).to be_empty
  end

  it "does not render token counts when all are zero" do
    expect(rendered.text).not_to include("in:")
    expect(rendered.text).not_to include("out:")
    expect(rendered.text).not_to include("cached:")
  end

  it "does not render the tool calls section when empty" do
    expect(rendered.text).not_to include("Tool Calls")
  end

  context "when content is blank" do
    let(:message) do
      build_stubbed(:message,
                    role: "tool",
                    content: nil,
                    thinking_text: nil,
                    created_at: Time.zone.parse("2026-04-08 10:00:00"))
    end

    it "renders the no-content placeholder" do
      expect(rendered.text).to include("No text content")
    end
  end

  context "when thinking_text is present" do
    let(:message) do
      build_stubbed(:message,
                    role: "assistant",
                    content: "Answer",
                    thinking_text: "I am thinking...",
                    created_at: Time.zone.parse("2026-04-08 10:00:00"))
    end

    it "renders the thinking disclosure" do
      expect(rendered.css("details")).to be_present
      expect(rendered.css("details summary").text.strip).to eq("Thinking")
    end

    it "renders the thinking text" do
      expect(rendered.text).to include("I am thinking...")
    end
  end

  context "when token counts are present" do
    let(:tokens) { RubyLLM::Tokens.new(input: 100, output: 50, cache_read: 20) }
    let(:message) do
      build_stubbed(:message,
                    role: "assistant",
                    content: "Hi",
                    thinking_text: nil,
                    created_at: Time.zone.parse("2026-04-08 10:00:00"))
    end

    it "renders input tokens" do
      expect(rendered.text).to include("in: 100")
    end

    it "renders output tokens" do
      expect(rendered.text).to include("out: 50")
    end

    it "renders cached tokens" do
      expect(rendered.text).to include("cached: 20")
    end
  end

  context "when tool calls are present" do
    let(:tool_call) do
      RubyLLM::ToolCall.new(id: "call_abc123", name: "list_emails", arguments: { "limit" => 10 })
    end
    let(:tool_calls) { { tool_call.id => tool_call } }

    it "renders the tool calls section header" do
      expect(rendered.text).to include("Tool Calls")
    end

    it "renders the tool call name" do
      expect(rendered.text).to include("list_emails")
    end

    it "renders the tool call id" do
      expect(rendered.text).to include("call_abc123")
    end

    it "renders the arguments via JsonDisclosureComponent" do
      expect(rendered.css("details")).to be_present
      expect(rendered.text).to include('"limit"')
    end
  end

  describe "#role_container_classes" do
    it "returns blue classes for user role" do
      expect(component.role_container_classes).to eq("bg-blue-50 border-blue-200")
    end

    context "with assistant role" do
      let(:message) { build_stubbed(:message, role: "assistant", content: nil, thinking_text: nil, created_at: Time.zone.now) }

      before { allow(message).to receive_messages(tool_calls: {}, tokens: tokens) }

      it "returns white/gray classes" do
        expect(component.role_container_classes).to eq("bg-white border-gray-200")
      end
    end

    context "with unknown role" do
      let(:message) { build_stubbed(:message, role: "system", content: nil, thinking_text: nil, created_at: Time.zone.now) }

      before { allow(message).to receive_messages(tool_calls: {}, tokens: tokens) }

      it "returns the default classes" do
        expect(component.role_container_classes).to eq("bg-gray-50 border-gray-200")
      end
    end
  end
end
