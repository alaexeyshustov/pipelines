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
      it "is valid with a name and a registered executor class" do
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "Emails::FetchExecutor")
        expect(action).to be_valid
      end

      it "is invalid without agent_class" do
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: nil)
        expect(action).not_to be_valid
        expect(action.errors[:agent_class]).to include(/can't be blank/)
      end

      it "rejects an unregistered class name" do
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "NotInRegistry")
        expect(action).not_to be_valid
        expect(action.errors[:agent_class]).to include(/must be a registered executor/)
      end

      it "is invalid when agent_id is present" do
        action = build(:orchestration_action, kind: :service, agent: nil, agent_class: "Emails::FetchExecutor")
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
    it "does not expose the dropped LLM config attributes" do
      action = build(:orchestration_action)
      %i[prompt model tools output_schema input_schema schema_class].each do |attr|
        expect(action).not_to respond_to(attr)
      end
    end
  end
end
