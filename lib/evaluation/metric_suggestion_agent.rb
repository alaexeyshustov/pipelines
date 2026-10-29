module Evaluation
  # Suggests metrics shaped like Evaluation::Metric rows: kind (probability | score | choice), levels / options
  # and a pass threshold. Options are an array here (strict schemas have no free-form maps); the suggester turns
  # them into the {option => {description, value}} hash stored in Metric#levels.
  class MetricSuggestionAgent < AuxiliaryAgent
    temperature 0

    schema do
      # rubocop:disable Metrics/BlockLength -- nested schema DSL
      array :metrics do
        object do
          string :name, description: "Short snake_case metric name"
          string :description, description: "Rubric: what is judged and what good looks like"
          number :weight, minimum: 0, maximum: 1, description: "Relative importance, 0.0..1.0"
          string :kind, enum: %w[probability score choice],
                        description: "probability: yes/no criterion; score: ordered quality levels; choice: named options"
          array :levels, of: :string,
                         description: "kind=score: 3 to 5 level descriptions ordered worst to best. Otherwise empty."
          array :options, description: "kind=choice: 2 to 5 named options. Otherwise empty." do
            object do
              string :name, description: "Option name"
              string :description, description: "When this option applies"
              number :value, minimum: 0, maximum: 1, description: "Quality of this option, 1.0 best"
            end
          end
          number :minimum, minimum: 0, maximum: 1,
                           description: "Pass threshold on the normalized 0.0..1.0 grade for this metric"
        end
      end
      # rubocop:enable Metrics/BlockLength
    end

    instructions <<~PROMPT
      You are an evaluation designer. Given an AI agent's system prompt, suggest 3 to 7 metrics that measure the
      quality of its outputs. Prefer probability (yes/no) criteria for objective checks, score (ordered levels,
      worst to best) for graded qualities, and choice only when outcomes are categorical with different quality.
    PROMPT
  end
end
