module Evaluation
  class MetricDefinitionFieldsComponentPreview < ViewComponent::Preview
    def probability
      render(Evaluation::MetricDefinitionFieldsComponent.new)
    end

    def score
      render(Evaluation::MetricDefinitionFieldsComponent.new(kind: "score", minimum: 0.6, levels: [ "Wrong", "Partly right", "Fully right" ]))
    end

    def choice
      levels = { "exact" => { "description" => "Exact match", "value" => 1.0 }, "close" => { "description" => "Close", "value" => 0.5 } }
      render(Evaluation::MetricDefinitionFieldsComponent.new(kind: "choice", minimum: 0.5, levels: levels))
    end
  end
end
