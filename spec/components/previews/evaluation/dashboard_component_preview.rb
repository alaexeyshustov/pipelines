module Evaluation
  class DashboardComponentPreview < ViewComponent::Preview
    def default
      summary = OpenStruct.new(
        agent_name: "ClassifyAgent",
        latest_experiment: OpenStruct.new(id: 1, name: "Experiment #42"),
        latest_score: 0.875,
        active_prompt_version: 3,
        sample_count: 120,
        score_history: [
          { created_at: "2024-01-01", avg_score: 0.8 },
          { created_at: "2024-01-15", avg_score: 0.85 },
          { created_at: "2024-02-01", avg_score: 0.875 }
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
