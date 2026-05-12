# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::DashboardComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  def build_summary(overrides = {})
    Evaluation::DashboardController::AgentSummary.new(
      agent_name: "TestAgent",
      latest_experiment: nil,
      latest_score: nil,
      active_prompt_version: nil,
      sample_count: 0,
      score_history: [],
      **overrides
    )
  end

  context "with no experiments (nil latest_experiment)" do
    let(:component) { described_class.new(summary: build_summary) }

    it "renders agent name" do
      expect(rendered.text).to include("TestAgent")
    end

    it "renders em dash for missing score" do
      expect(rendered.text).to include("—")
    end

    it "renders 0 sample count" do
      expect(rendered.text).to include("0")
    end

    it "does not render a 'View Experiment' link" do
      expect(rendered.css("a[href*='experiments/']").select { |a| a.text.strip == "View Experiment" }).to be_empty
    end
  end

  context "with one completed experiment" do
    let(:experiment) { create(:leva_experiment, status: :completed) }
    let(:summary) do
      build_summary(
        agent_name: experiment.prompt.name,
        latest_experiment: experiment,
        latest_score: 3.8,
        active_prompt_version: 2,
        sample_count: 10
      )
    end
    let(:component) { described_class.new(summary: summary) }

    it "renders the experiment id" do
      expect(rendered.text).to include(experiment.id.to_s)
    end

    it "renders the average score" do
      expect(rendered.text).to include("3.8")
    end

    it "renders the active prompt version" do
      expect(rendered.text).to include("v2")
    end

    it "renders the sample count" do
      expect(rendered.text).to include("10")
    end

    it "links to the experiment" do
      expect(rendered.css("a[href*='experiments']")).to be_present
    end
  end

  context "with many experiments — score-over-time chart present" do
    let(:experiment) { create(:leva_experiment) }
    let(:score_history) do
      [
        { created_at: "2026-01-01", avg_score: 3.0 },
        { created_at: "2026-02-01", avg_score: 4.0 }
      ]
    end
    let(:component) do
      described_class.new(summary: build_summary(
        agent_name: experiment.prompt.name,
        latest_experiment: experiment,
        sample_count: 5,
        score_history: score_history
      ))
    end

    it "renders the ScoreOverTimeComponent chart wrapper" do
      expect(rendered.css("[data-controller='evaluation--score-chart']")).to be_present
    end
  end

  context "with a known agent_name" do
    let(:component) { described_class.new(summary: build_summary(agent_name: "TestAgent")) }

    it "renders a Run Evaluation link pointing to new_evaluation_experiment_path" do
      expect(rendered.css("a[href*='experiments/new']")).to be_present
    end

    it "passes agent_name as query param in the Run Evaluation link" do
      expect(rendered.css("a[href*='agent_name=TestAgent']")).to be_present
    end
  end
end
