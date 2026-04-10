# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::StepRunComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:pipeline) { build_stubbed(:orchestration_pipeline, id: 1) }
  let(:step) { build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "Parse Emails", position: 1) }
  let(:entry) { { step: step, action_runs: [], derived_status: "pending" } }
  let(:component) { described_class.new(entry: entry) }

  it "renders the step run wrapper" do
    expect(rendered.css("[data-testid='step-run']")).to be_present
  end

  it "renders the step position" do
    expect(rendered.css("[data-testid='step-position']").text.strip).to eq("1")
  end

  it "renders the step name" do
    expect(rendered.css("[data-testid='step-name']").text.strip).to eq("Parse Emails")
  end

  it "renders the derived status badge" do
    expect(rendered.text).to include("Pending")
  end

  it "renders the empty message when there are no action runs" do
    expect(rendered.css("[data-testid='no-action-runs']")).to be_present
    expect(rendered.text).to include("No action runs recorded for this step.")
  end

  context "when action_runs are present" do
    let(:action_run) do
      step_action = build_stubbed(:orchestration_step_action,
                                  action: build_stubbed(:orchestration_action, name: "Classify Agent"))
      build_stubbed(:orchestration_action_run,
                    step_action: step_action,
                    status: "completed",
                    started_at: nil,
                    finished_at: nil,
                    error: nil,
                    input: nil,
                    output: nil)
    end
    let(:entry) { { step: step, action_runs: [ action_run ], derived_status: "completed" } }

    it "does not render the empty message" do
      expect(rendered.css("[data-testid='no-action-runs']")).to be_empty
    end

    it "renders the action run" do
      expect(rendered.css("[data-testid='action-run']")).to be_present
    end

    it "renders the action name within the action run" do
      expect(rendered.text).to include("Classify Agent")
    end
  end

  context "when derived_status is failed" do
    let(:entry) { { step: step, action_runs: [], derived_status: "failed" } }

    it "renders the failed status badge" do
      expect(rendered.text).to include("Failed")
    end
  end
end
