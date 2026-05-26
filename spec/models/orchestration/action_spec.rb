require "rails_helper"

RSpec.describe Orchestration::Action do
  it { expect(described_class.table_name).to eq("orchestration_actions") }

  describe "validations" do
    context "with kind: :agent" do
      it "is valid with a name and an associated agent" do
        action = build(:orchestration_action, kind: :agent)
        expect(action).to be_valid
      end

      it "is invalid without an agent_id" do
        action = build(:orchestration_action, kind: :agent, agent: nil)
        expect(action).not_to be_valid
        expect(action.errors[:agent_id]).to include(/must be present/)
      end

      it "is invalid when agent_class is present" do
        action = build(:orchestration_action, kind: :agent, agent_class: "SomeClass")
        expect(action).not_to be_valid
        expect(action.errors[:agent_class]).to include(/must be blank/)
      end
    end

    context "with kind: :service" do
      it "is valid with a name and a valid executable class" do
        stub_const("MyExecutable", Class.new { include Orchestration::Executable })
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "MyExecutable")
        expect(action).to be_valid
      end

      it "is invalid without agent_class" do
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: nil)
        expect(action).not_to be_valid
        expect(action.errors[:agent_class]).to include(/can't be blank/)
      end

      it "rejects non-existent class" do
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "NonExistent::Klass")
        expect(action).not_to be_valid
        expect(action.errors[:agent_class]).to include(/must be an existing constant/)
      end

      it "rejects a class that does not include Orchestration::Executable" do
        stub_const("RegularClass", Class.new)
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "RegularClass")
        expect(action).not_to be_valid
        expect(action.errors[:agent_class]).to include(/must include Orchestration::Executable/)
      end

      it "is invalid when agent_id is present" do
        stub_const("MyExecutable", Class.new { include Orchestration::Executable })
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "MyExecutable")
        action.agent_id = 999
        expect(action).not_to be_valid
        expect(action.errors[:agent_id]).to include(/must be blank/)
      end
    end

    it_behaves_like "requires attribute", :name, :orchestration_action
  end

  describe "associations" do
    it "blocks deletion when referenced by a step_action" do
      action = create(:orchestration_action)
      create(:orchestration_step_action, action: action)
      action.destroy
      expect(action.errors[:base]).not_to be_empty
      expect(described_class.exists?(action.id)).to be true
    end
  end

  describe "columns" do
    it "does not expose dropped LLM config DB attributes" do
      action = build(:orchestration_action)
      %i[prompt model tools output_schema schema_class].each do |attr|
        expect(action).not_to respond_to(attr)
      end
    end
  end

  describe '#input_schema' do
    context 'when action is agent-kind' do
      it 'delegates to the associated agent' do
        schema = { "type" => "object", "properties" => { "emails" => { "type" => "array" } } }
        agent  = create(:orchestration_agent, input_schema: schema)
        action = create(:orchestration_action, agent:)

        expect(action.input_schema).to eq(schema)
      end

      it 'returns nil when the agent has no input_schema' do
        agent  = create(:orchestration_agent, input_schema: nil)
        action = create(:orchestration_action, agent:)

        expect(action.input_schema).to be_nil
      end
    end

    context 'when action is service-kind' do
      it 'delegates to the service class input_schema' do
        stub_const("MyExecutable", Class.new do
          include Orchestration::Executable
          input_schema(topic: { "type" => "string" })
          def self.call(topic:, **); end
        end)
        action = create(:orchestration_action, :service_kind, agent_class: "MyExecutable")

        expect(action.input_schema["properties"].keys).to include("topic")
      end

      it 'returns nil when agent_class is blank' do
        action = build(:orchestration_action, :service_kind, agent_class: nil)
        expect(action.input_schema).to be_nil
      end
    end
  end
end
