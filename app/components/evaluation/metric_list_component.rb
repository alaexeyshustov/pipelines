# frozen_string_literal: true

module Evaluation
  class MetricListComponent < ViewComponent::Base
    def initialize(metrics:)
      @metrics = metrics
    end
  end
end
