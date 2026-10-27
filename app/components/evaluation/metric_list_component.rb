module Evaluation
  class MetricListComponent < ViewComponent::Base
    def initialize(metrics:)
      @metrics = metrics
    end
  end
end
