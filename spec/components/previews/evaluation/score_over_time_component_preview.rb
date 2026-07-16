
module Evaluation
  class ScoreOverTimeComponentPreview < ViewComponent::Preview
    def default
      data = [
        { date: "2024-01-01", score: 72.0 },
        { date: "2024-01-15", score: 78.5 },
        { date: "2024-02-01", score: 83.2 },
        { date: "2024-02-15", score: 87.5 }
      ]
      render(Evaluation::ScoreOverTimeComponent.new(agent_name: "ClassifyAgent", data: data))
    end

    def no_data
      render(Evaluation::ScoreOverTimeComponent.new(agent_name: "NewAgent", data: []))
    end
  end
end
