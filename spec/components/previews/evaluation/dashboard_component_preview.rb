# frozen_string_literal: true

module Evaluation
  class DashboardComponentPreview < ViewComponent::Preview
    def default
      summary = OpenStruct.new(
        agent_name: "ClassifyAgent",
        latest_experiment: OpenStruct.new(id: 1, name: "Experiment #42"),
        latest_score: 87.5,
        active_prompt_version: 3,
        sample_count: 120,
        score_history: [
          { date: "2024-01-01", score: 80.0 },
          { date: "2024-01-15", score: 85.0 },
          { date: "2024-02-01", score: 87.5 }
        ]
      )
      render(Evaluation::DashboardComponent.new(summary: summary))
    end

    def no_data
      summary = OpenStruct.new(
        agent_name: "NewAgent",
        latest_experiment: nil,
        latest_score: nil,
        active_prompt_version: nil,
        sample_count: 0,
        score_history: []
      )
      render(Evaluation::DashboardComponent.new(summary: summary))
    end
  end
end
