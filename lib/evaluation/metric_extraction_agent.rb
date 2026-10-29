module Evaluation
  class MetricExtractionAgent < AuxiliaryAgent
    schema do
      array :metrics do
        object do
          string :name, description: "snake_case, concise"
          string :description, description: "Rubric text explaining what to measure and how to score it"
        end
      end
    end

    instructions <<~PROMPT
      You are an evaluation expert. Given an agent's instructions, identify its evaluable behaviors and return
      candidate metrics. Each metric has a name (snake_case, concise) and a description (rubric text explaining
      what to measure and how to score it).
    PROMPT
  end
end
