# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::ActionRunComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:action) { build_stubbed(:orchestration_action, name: "Classify Agent") }
  let(:step_action) do
    build_stubbed(:orchestration_step_action, action: action)
  end
  let(:action_run) do
    build_stubbed(:orchestration_action_run,
                  step_action: step_action,
                  status: "completed",
                  started_at: Time.zone.parse("2026-04-08 10:00:00"),
                  finished_at: Time.zone.parse("2026-04-08 10:00:05"),
                  error: nil,
                  input: nil,
                  output: nil)
  end
  let(:component) { described_class.new(action_run: action_run) }

  it "renders the action run wrapper" do
    expect(rendered.css("[data-testid='action-run']")).to be_present
  end

  it "renders the action name" do
    expect(rendered.text).to include("Classify Agent")
  end

  it "renders the status badge" do
    expect(rendered.text).to include("Completed")
  end

  it "renders formatted started_at" do
    expect(rendered.text).to include("10:00:00")
  end

  it "renders formatted finished_at" do
    expect(rendered.text).to include("10:00:05")
  end

  it "does not render an error when absent" do
    expect(rendered.css("[data-testid='action-run-error']")).to be_empty
  end

  it "does not render input details when absent" do
    expect(rendered.css("details")).to be_empty
  end

  context "when started_at is nil" do
    let(:action_run) do
      build_stubbed(:orchestration_action_run,
                    step_action: step_action,
                    status: "pending",
                    started_at: nil,
                    finished_at: nil,
                    error: nil,
                    input: nil,
                    output: nil)
    end

    it "renders no timestamps" do
      expect(rendered.css("[data-testid='action-run-timestamps']").text.strip).to be_empty
    end
  end

  context "when error is present" do
    let(:action_run) do
      build_stubbed(:orchestration_action_run,
                    step_action: step_action,
                    status: "failed",
                    started_at: nil,
                    finished_at: nil,
                    error: "Unexpected failure",
                    input: nil,
                    output: nil)
    end

    it "renders the error message" do
      expect(rendered.text).to include("Unexpected failure")
    end

    it "renders the error banner" do
      expect(rendered.css("[data-testid='action-run-error']")).to be_present
    end
  end

  context "when input is present" do
    let(:action_run) do
      build_stubbed(:orchestration_action_run,
                    step_action: step_action,
                    status: "completed",
                    started_at: nil,
                    finished_at: nil,
                    error: nil,
                    input: { "key" => "value" },
                    output: nil)
    end

    it "renders input details" do
      expect(rendered.css("details summary").first.text.strip).to eq("Input")
      expect(rendered.css("pre").first.text).to include('"key"')
    end
  end

  context "when output is present" do
    let(:action_run) do
      build_stubbed(:orchestration_action_run,
                    step_action: step_action,
                    status: "completed",
                    started_at: nil,
                    finished_at: nil,
                    error: nil,
                    input: nil,
                    output: { "result" => "ok" })
    end

    it "renders output details" do
      expect(rendered.css("details summary").first.text.strip).to eq("Output")
      expect(rendered.css("pre").first.text).to include('"result"')
    end
  end

  describe "#action_name" do
    it "delegates to the step_action's action name" do
      expect(component.action_name).to eq("Classify Agent")
    end
  end

  describe "#formatted_started_at" do
    it "returns the time formatted as HH:MM:SS" do
      expect(component.formatted_started_at).to eq("10:00:00")
    end

    context "when started_at is nil" do
      let(:action_run) do
        build_stubbed(:orchestration_action_run,
                      step_action: step_action,
                      status: "pending",
                      started_at: nil,
                      finished_at: nil,
                      error: nil,
                      input: nil,
                      output: nil)
      end

      it "returns nil" do
        expect(component.formatted_started_at).to be_nil
      end
    end
  end

  describe "#formatted_finished_at" do
    it "returns the time formatted as HH:MM:SS" do
      expect(component.formatted_finished_at).to eq("10:00:05")
    end

    context "when finished_at is nil" do
      let(:action_run) do
        build_stubbed(:orchestration_action_run,
                      step_action: step_action,
                      status: "running",
                      started_at: Time.zone.parse("2026-04-08 10:00:00"),
                      finished_at: nil,
                      error: nil,
                      input: nil,
                      output: nil)
      end

      it "returns nil" do
        expect(component.formatted_finished_at).to be_nil
      end
    end
  end
end
