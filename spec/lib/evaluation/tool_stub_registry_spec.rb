# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::ToolStubRegistry do
  describe "#lookup" do
    it "returns the stubbed result for a matching tool call" do
      registry = described_class.new([
        { tool_name: "my_tool", arguments: { "key" => "value" }, result: "stubbed_result" }
      ])
      expect(registry.lookup(tool_name: "my_tool", arguments: { "key" => "value" })).to eq("stubbed_result")
    end

    it "raises ToolStubError when no expected call is registered" do
      registry = described_class.new([])
      expect { registry.lookup(tool_name: "unknown", arguments: {}) }
        .to raise_error(Evaluation::ToolStubRegistry::ToolStubError, /unknown/)
    end

    it "raises ToolStubError after all expected calls are consumed" do
      registry = described_class.new([
        { tool_name: "my_tool", arguments: {}, result: "first" }
      ])
      registry.lookup(tool_name: "my_tool", arguments: {})
      expect { registry.lookup(tool_name: "my_tool", arguments: {}) }
        .to raise_error(Evaluation::ToolStubRegistry::ToolStubError)
    end

    it "consumes calls in order (FIFO)" do
      registry = described_class.new([
        { tool_name: "t", arguments: {}, result: "first" },
        { tool_name: "t", arguments: {}, result: "second" }
      ])
      expect(registry.lookup(tool_name: "t", arguments: {})).to eq("first")
      expect(registry.lookup(tool_name: "t", arguments: {})).to eq("second")
    end

    it "warns but still returns result when arguments do not match" do
      registry = described_class.new([
        { tool_name: "t", arguments: { "x" => 1 }, result: "ok" }
      ])
      allow(Rails.logger).to receive(:warn)
      result = registry.lookup(tool_name: "t", arguments: { "x" => 99 })
      expect(result).to eq("ok")
      expect(Rails.logger).to have_received(:warn).with(/mismatch/)
    end

    it "normalizes symbol keys when comparing arguments" do
      registry = described_class.new([
        { tool_name: "t", arguments: { x: 1 }, result: "sym" }
      ])
      expect(registry.lookup(tool_name: "t", arguments: { "x" => 1 })).to eq("sym")
    end
  end
end
