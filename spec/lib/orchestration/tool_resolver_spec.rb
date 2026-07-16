
require "rails_helper"

RSpec.describe Orchestration::ToolResolver do
  subject(:resolved) { described_class.new(agent: agent_record).resolve }

  let(:agent_record) { create(:orchestration_agent, tools: [ "Records::TempFileTool" ]) }

  describe "#resolve" do
    it "resolves configured tool class names via the registry" do
      expect(resolved).to eq([ Records::TempFileTool ])
    end

    it "raises ArgumentError when a tool is outside allowed namespaces" do
      allow(agent_record).to receive(:tools).and_return([ "Kernel::Exec" ])
      expect { resolved }.to raise_error(ArgumentError, /Unknown tool class: Kernel::Exec/)
    end

    it "raises ArgumentError when a tool class cannot be found" do
      allow(agent_record).to receive(:tools).and_return([ "Records::NonExistentTool" ])
      expect { resolved }.to raise_error(ArgumentError, /Unknown tool class: Records::NonExistentTool/)
    end

    it "raises ArgumentError when the resolved constant is not a registered RubyLLM::Tool subclass" do
      allow(agent_record).to receive(:tools).and_return([ "Records::ModelResolver" ])
      expect { resolved }.to raise_error(ArgumentError, /Unknown tool class: Records::ModelResolver/)
    end

    context "when configured tools are blank" do
      let(:agent_record) { create(:orchestration_agent, name: "Emails::FallbackAgent", tools: nil) }

      it "falls back to the agent class's declared tools" do
        fake_agent_class = Class.new do
          def self.tools
            [ Records::TempFileTool ]
          end
        end
        stub_const("Emails::FallbackAgent", fake_agent_class)

        expect(resolved).to eq([ Records::TempFileTool ])
      end

      it "raises ArgumentError when the agent class fallback does not apply" do
        expect { resolved }.to raise_error(ArgumentError, /agent "Emails::FallbackAgent" has no configured tools/)
      end
    end
  end
end
