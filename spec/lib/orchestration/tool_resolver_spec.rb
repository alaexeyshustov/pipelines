require "rails_helper"

RSpec.describe Orchestration::ToolResolver do
  subject(:resolved) { described_class.new(agent: agent_record).resolve }

  let(:agent_record) { create(:orchestration_agent, tools: [ "Records::TempFileTool" ]) }

  describe ".lookup" do
    it "returns the registry value for a name" do
      expect(described_class.lookup("Records::TempFileTool")).to eq(Records::TempFileTool)
    end

    it "returns the classifier-bound subclass for Emails::ClassifyTool" do
      tool = described_class.lookup("Emails::ClassifyTool")
      expect(tool.classifier).to eq(Orchestration::Agents::EmailsClassifier)
    end

    it "returns the same object as REGISTRY" do
      described_class::REGISTRY.each { |name, klass| expect(described_class.lookup(name)).to equal(klass) }
    end

    [ "Kernel::Exec", "Records::NonExistentTool", "Records::ModelResolver", "Emails::Adapters::GmailAdapter", "" ].each do |name|
      it "raises ArgumentError for #{name.inspect}" do
        expect { described_class.lookup(name) }.to raise_error(ArgumentError, /Unknown tool class: #{Regexp.escape(name)}/)
      end
    end
  end

  describe "REGISTRY" do
    it "has exactly the keys of Orchestration::Agent.available_tools" do
      expect(described_class::REGISTRY.keys).to match_array(Orchestration::Agent.available_tools)
    end
  end

  describe "#resolve" do
    it "resolves configured tool class names via the registry" do
      expect(resolved).to eq([ Records::TempFileTool ])
    end

    it "binds the orchestration classifier into Emails::ClassifyTool" do
      allow(agent_record).to receive(:tools).and_return([ "Emails::ClassifyTool" ])
      expect(resolved.first.classifier).to eq(Orchestration::Agents::EmailsClassifier)
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
        stub_const("Emails::FallbackAgent", Class.new(RubyLLM::Agent) { tools Records::TempFileTool })

        expect(resolved).to eq([ Records::TempFileTool ])
      end

      it "raises when the agent name resolves to a class that is not a RubyLLM::Agent" do
        stub_const("Emails::FallbackAgent", Class.new { def self.tools = [ Records::TempFileTool ] })

        expect { resolved }.to raise_error(ArgumentError, /agent "Emails::FallbackAgent" has no configured tools/)
      end

      it "uses the tools of a RubyLLM::Agent subclass" do
        stub_const("Emails::FallbackAgent", Class.new(RubyLLM::Agent) { tools Records::ReadRowsTool })

        expect(resolved).to eq([ Records::ReadRowsTool ])
      end

      it "returns no tools for a RubyLLM::Agent subclass that declares none" do
        stub_const("Emails::FallbackAgent", Class.new(RubyLLM::Agent))

        expect(resolved).to eq([])
      end

      it "raises ArgumentError when the agent class fallback does not apply" do
        expect { resolved }.to raise_error(ArgumentError, /agent "Emails::FallbackAgent" has no configured tools/)
      end
    end
  end
end
