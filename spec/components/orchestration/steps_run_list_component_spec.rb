
require "rails_helper"

RSpec.describe Orchestration::StepsRunListComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:pipeline) { build_stubbed(:orchestration_pipeline, id: 1) }
  let(:step) { build_stubbed(:orchestration_step, id: 10, pipeline: pipeline, name: "Parse Emails", position: 1) }
  let(:action_runs_by_step) { {} }
  let(:run) { build_stubbed(:orchestration_pipeline_run, pipeline: pipeline, initial_input: nil) }

  let(:component) do
    described_class.new(pipeline: pipeline, run: run, action_runs_by_step: action_runs_by_step)
  end

  before do
    allow(pipeline).to receive(:steps).and_return([ step ])
  end

  it "renders a grid container" do
    expect(rendered.css("div.grid")).to be_present
  end

  it "renders a step run for each step" do
    expect(rendered.css("[data-testid='step-run']")).to be_present
  end

  it "renders the step name" do
    expect(rendered.text).to include("Parse Emails")
  end

  context "when action_runs exist for a step" do
    let(:action_run) do
      sa = build_stubbed(:orchestration_step_action, id: 1, step: step,
                         action: build_stubbed(:orchestration_action, name: "Classify Agent"),
                         output_key: "classification")
      build_stubbed(:orchestration_action_run, step_action: sa, status: "completed",
                    started_at: nil, finished_at: nil, error: nil, input: nil, output: nil)
    end
    let(:action_runs_by_step) { { step.id => [ action_run ] } }

    it "renders the action run" do
      expect(rendered.css("[data-testid='action-run']")).to be_present
    end
  end
end
