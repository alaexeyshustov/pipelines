module Evaluation
  class ScoreOverTimeComponentPreview < ViewComponent::Preview
    def default
      data = [
        { created_at: "2024-01-01", avg_score: 0.72 },
        { created_at: "2024-01-15", avg_score: 0.785 },
        { created_at: "2024-02-01", avg_score: 0.832 },
        { created_at: "2024-02-15", avg_score: 0.875 }
      ]
      render(Evaluation::ScoreOverTimeComponent.new(agent_name: "ClassifyAgent", data: data))
    end

    def no_data
      render(Evaluation::ScoreOverTimeComponent.new(agent_name: "NewAgent", data: []))
    end
  end
end
