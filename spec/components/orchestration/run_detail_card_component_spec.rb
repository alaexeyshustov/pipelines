# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::RunDetailCardComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:run) do
    build_stubbed(:orchestration_pipeline_run,
                  triggered_by: "manual",
                  started_at: Time.zone.parse("2026-04-08 10:00:00"),
                  finished_at: Time.zone.parse("2026-04-08 10:01:00"),
                  initial_input: nil,
                  error: nil)
  end
  let(:component) { described_class.new(run: run) }

  it "renders the detail card wrapper" do
    expect(rendered.css("[data-testid='run-detail-card']")).to be_present
  end

  it "renders triggered_by" do
    expect(rendered.css("dd").first.text.strip).to eq("manual")
  end

  it "renders formatted started_at" do
    expect(rendered.text).to include("2026-04-08 10:00:00")
  end

  it "renders formatted finished_at" do
    expect(rendered.text).to include("2026-04-08 10:01:00")
  end

  it "renders duration" do
    expect(rendered.text).to include("1 minute")
  end

  it "does not render an initial input section when absent" do
    expect(rendered.css("details")).to be_empty
  end

  it "does not render an error banner when absent" do
    expect(rendered.css("[data-testid='run-error']")).to be_empty
  end

  context "when triggered_by is nil" do
    let(:run) do
      build_stubbed(:orchestration_pipeline_run,
                    triggered_by: nil, started_at: nil, finished_at: nil,
                    initial_input: nil, error: nil)
    end

    it "renders an em-dash for triggered_by" do
      expect(rendered.css("dd").first.text.strip).to eq("—")
    end
  end

  context "when started_at is nil" do
    let(:run) do
      build_stubbed(:orchestration_pipeline_run,
                    started_at: nil, finished_at: nil,
                    initial_input: nil, error: nil)
    end

    it "renders em-dash for started" do
      expect(rendered.css("dd")[1].text.strip).to eq("—")
    end
  end

  context "when finished_at is nil" do
    let(:run) do
      build_stubbed(:orchestration_pipeline_run,
                    started_at: Time.zone.parse("2026-04-08 10:00:00"),
                    finished_at: nil, initial_input: nil, error: nil)
    end

    it "renders em-dash for finished" do
      expect(rendered.css("dd")[2].text.strip).to eq("—")
    end

    it "renders em-dash for duration" do
      expect(rendered.css("dd")[3].text.strip).to eq("—")
    end
  end

  context "when initial_input is present" do
    let(:run) do
      build_stubbed(:orchestration_pipeline_run,
                    started_at: nil, finished_at: nil, error: nil,
                    initial_input: { "key" => "value" })
    end

    it "renders a details/summary for initial input" do
      expect(rendered.css("details")).to be_present
      expect(rendered.css("details summary").text.strip).to eq("Initial Input")
    end

    it "renders the JSON content inside a pre tag" do
      expect(rendered.css("pre").text).to include('"key"')
    end
  end

  context "when error is present" do
    let(:run) do
      build_stubbed(:orchestration_pipeline_run,
                    started_at: nil, finished_at: nil, initial_input: nil,
                    error: "Something went wrong")
    end

    it "renders the error message" do
      expect(rendered.text).to include("Something went wrong")
    end

    it "renders the error inside the error banner" do
      expect(rendered.css("[data-testid='run-error']")).to be_present
    end
  end

  describe "#formatted_started_at" do
    it "returns formatted timestamp when present" do
      expect(component.formatted_started_at).to eq("2026-04-08 10:00:00")
    end

    context "when started_at is nil" do
      let(:run) { build_stubbed(:orchestration_pipeline_run, started_at: nil, finished_at: nil, initial_input: nil, error: nil) }

      it "returns em-dash" do
        expect(component.formatted_started_at).to eq("—")
      end
    end
  end

  describe "#formatted_finished_at" do
    it "returns formatted timestamp when present" do
      expect(component.formatted_finished_at).to eq("2026-04-08 10:01:00")
    end

    context "when finished_at is nil" do
      let(:run) { build_stubbed(:orchestration_pipeline_run, started_at: nil, finished_at: nil, initial_input: nil, error: nil) }

      it "returns em-dash" do
        expect(component.formatted_finished_at).to eq("—")
      end
    end
  end

  describe "#duration" do
    it "returns a human-readable duration when both timestamps present" do
      expect(component.duration).to eq("1 minute")
    end

    context "when started_at is nil" do
      let(:run) { build_stubbed(:orchestration_pipeline_run, started_at: nil, finished_at: nil, initial_input: nil, error: nil) }

      it "returns em-dash" do
        expect(component.duration).to eq("—")
      end
    end

    context "when finished_at is nil" do
      let(:run) do
        build_stubbed(:orchestration_pipeline_run,
                      started_at: Time.zone.parse("2026-04-08 10:00:00"),
                      finished_at: nil, initial_input: nil, error: nil)
      end

      it "returns em-dash" do
        expect(component.duration).to eq("—")
      end
    end
  end
end
