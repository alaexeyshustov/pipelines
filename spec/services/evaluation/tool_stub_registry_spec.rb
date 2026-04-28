require "rails_helper"

RSpec.describe Evaluation::ToolStubRegistry do
  subject(:registry) { described_class.new(expected_tool_calls) }

  let(:expected_tool_calls) do
    [
      { tool_name: "temp_file", arguments: { "action" => "read", "filename" => "out.txt" }, result: "file contents" },
      { tool_name: "temp_file", arguments: { "action" => "write", "filename" => "result.txt" }, result: "written" },
      { tool_name: "get_email", arguments: { "provider" => "gmail", "message_id" => "123" }, result: "email body" }
    ]
  end


  describe "#lookup" do
    it "returns historical results in order per tool name" do
      first = registry.lookup(tool_name: "temp_file", arguments: { "action" => "read", "filename" => "out.txt" })
      second = registry.lookup(tool_name: "temp_file", arguments: { "action" => "write", "filename" => "result.txt" })

      expect(first).to eq("file contents")
      expect(second).to eq("written")
    end

    it "maintains separate queues per tool name" do
      email_result = registry.lookup(tool_name: "get_email", arguments: { "provider" => "gmail", "message_id" => "123" })
      file_result = registry.lookup(tool_name: "temp_file", arguments: { "action" => "read", "filename" => "out.txt" })

      expect(email_result).to eq("email body")
      expect(file_result).to eq("file contents")
    end

    it "normalizes symbol keys before comparison" do
      result = registry.lookup(tool_name: "temp_file", arguments: { action: "read", filename: "out.txt" })

      expect(result).to eq("file contents")
    end

    it "normalizes mixed string/symbol keys" do
      result = registry.lookup(tool_name: "temp_file", arguments: { "action" => "read", filename: "out.txt" })

      expect(result).to eq("file contents")
    end

    it "logs a mismatch warning but still returns the expected result" do
      allow(Rails.logger).to receive(:warn)

      result = registry.lookup(tool_name: "temp_file", arguments: { "action" => "read", "filename" => "WRONG.txt" })

      expect(result).to eq("file contents")
      expect(Rails.logger).to have_received(:warn).with(/mismatch/i)
    end

    it "logs a warning and returns nil when queue is empty" do
      allow(Rails.logger).to receive(:warn)

      registry.lookup(tool_name: "get_email", arguments: {})
      result = registry.lookup(tool_name: "get_email", arguments: {})

      expect(result).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/no expected call/i)
    end

    it "returns nil for unknown tool names" do
      allow(Rails.logger).to receive(:warn)

      result = registry.lookup(tool_name: "unknown_tool", arguments: {})

      expect(result).to be_nil
    end
  end
end
