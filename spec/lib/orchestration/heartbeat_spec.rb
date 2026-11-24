require "rails_helper"

RSpec.describe Orchestration::Heartbeat do
  include ActiveSupport::Testing::TimeHelpers

  let(:run) { create(:orchestration_pipeline_run, status: "running") }

  after { Orchestration::Current.reset }

  describe ".beat" do
    it "does nothing outside a pipeline run" do
      Orchestration::Current.pipeline_run = nil

      expect { described_class.beat }.not_to raise_error
    end

    it "makes no queries outside a pipeline run" do
      Orchestration::Current.pipeline_run = nil
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.beat }

      expect(count).to eq(0)
    end

    it "stamps heartbeat_at of the current run" do
      Orchestration::Current.pipeline_run = run

      freeze_time do
        described_class.beat

        expect(run.reload.heartbeat_at).to eq(Time.current)
      end
    end

    it "touches the run at most once a minute" do
      Orchestration::Current.pipeline_run = run
      start = Time.zone.local(2026, 4, 1, 12)

      travel_to(start) { described_class.beat }
      travel_to(start + 59.seconds) { described_class.beat }
      expect(run.reload.heartbeat_at).to eq(start)

      travel_to(start + 61.seconds) { described_class.beat }
      expect(run.reload.heartbeat_at).to eq(start + 61.seconds)
    end

    it "does not query the database for a beat inside the throttle window" do
      Orchestration::Current.pipeline_run = run
      start = Time.zone.local(2026, 4, 1, 12)
      travel_to(start) { described_class.beat }
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }

      travel_to(start + 10.seconds) do
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { 5.times { described_class.beat } }
      end

      expect(count).to eq(0)
    end
  end
end
