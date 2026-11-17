module Evaluation
  # Suggests metrics shaped like Evaluation::Metric rows: kind (probability | score | choice), levels / options
  # and a pass threshold. Options are an array here (strict schemas have no free-form maps); the suggester turns
  # them into the {option => {description, value}} hash stored in Metric#levels.
  class MetricSuggestionAgent < AuxiliaryAgent
    temperature 0

    schema MetricSuggestionSchema

    instructions <<~PROMPT
      You are an evaluation designer. Given an AI agent's system prompt, suggest 3 to 7 metrics that measure the
      quality of its outputs. Prefer probability (yes/no) criteria for objective checks, score (ordered levels,
      worst to best) for graded qualities, and choice only when outcomes are categorical with different quality.
    PROMPT
  end
end
