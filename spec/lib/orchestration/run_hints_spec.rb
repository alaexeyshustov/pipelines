require "rails_helper"

RSpec.describe Orchestration::RunHints do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:emails_list) { create(:orchestration_action, :service_kind, agent_class: "Orchestration::Executors::EmailsList") }
  let(:fetcher) { create(:orchestration_action, :service_kind, agent_class: "Orchestration::Executors::EmailsFetcher") }

  def add_step(position:, action:, enabled: true, action_position: 1)
    step = Orchestration::Step.find_by(pipeline:, position:) || create(:orchestration_step, pipeline:, position:, enabled:)
    create(:orchestration_step_action, step:, action:, position: action_position)
  end

  describe ".call" do
    it "returns the hints of the first step's executor when it defines run_hints" do
      create(:email_sync_cursor, provider: "gmail", last_synced_at: Time.utc(2026, 3, 20, 14, 3))
      add_step(position: 1, action: emails_list)

      expect(described_class.call(pipeline)).to eq("providers" => "Last synced: gmail 2026-03-20 14:03, yahoo never")
    end

    it "asks the executor class, once" do
      add_step(position: 1, action: emails_list)
      allow(Orchestration::Executors::EmailsList).to receive(:run_hints).and_return({ "providers" => "hint" })

      expect(described_class.call(pipeline)).to eq("providers" => "hint")
      expect(Orchestration::Executors::EmailsList).to have_received(:run_hints).once
    end

    it "returns an empty hash when the first executor has no run_hints hook" do
      add_step(position: 1, action: fetcher)

      expect(described_class.call(pipeline)).to eq({})
    end

    it "returns an empty hash when the first action is an agent" do
      add_step(position: 1, action: create(:orchestration_action))

      expect(described_class.call(pipeline)).to eq({})
    end

    it "returns an empty hash for a pipeline without steps" do
      expect(described_class.call(pipeline)).to eq({})
    end

    it "returns an empty hash for a step without actions" do
      create(:orchestration_step, pipeline:, position: 1)

      expect(described_class.call(pipeline)).to eq({})
    end

    it "only looks at the first enabled step" do
      add_step(position: 1, action: emails_list, enabled: false)
      add_step(position: 2, action: fetcher)

      expect(described_class.call(pipeline)).to eq({})
    end

    it "does not look past the first step: a later EmailsList step gives no hints" do
      add_step(position: 1, action: fetcher)
      add_step(position: 2, action: emails_list)

      expect(described_class.call(pipeline)).to eq({})
    end

    it "only looks at the first action of that step" do
      add_step(position: 1, action: fetcher, action_position: 1)
      add_step(position: 1, action: emails_list, action_position: 2)

      expect(described_class.call(pipeline)).to eq({})
    end

    it "returns an empty hash when the action's class is not in the registry" do
      action = create(:orchestration_action, :service_kind, agent_class: "Orchestration::Executors::EmailsList")
      action.update_column(:agent_class, "Gone::Executor")
      add_step(position: 1, action: action)

      expect(described_class.call(pipeline)).to eq({})
    end
  end
end
