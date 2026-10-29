module Evaluation
  class GradeDetailComponentPreview < ViewComponent::Preview
    def score
      result = OpenStruct.new(
        score: 0.75, passed: true, confidence: 0.82,
        raw: { "type" => "score", "score" => 1.5, "levels" => [ "Wrong", "Partly right", "Fully right" ],
               "probabilities" => { "Wrong" => 0.05, "Partly right" => 0.55, "Fully right" => 0.4 } }
      )
      render(Evaluation::GradeDetailComponent.new(result: result))
    end

    def probability_failed
      result = OpenStruct.new(score: 0.2, passed: false, confidence: nil, raw: { "type" => "probability", "probability" => 0.2 })
      render(Evaluation::GradeDetailComponent.new(result: result))
    end
  end
end
