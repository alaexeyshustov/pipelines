# frozen_string_literal: true

module Orchestration
  class NewStepComponent < ViewComponent::Base
    def initialize(pipeline:)
      @pipeline = pipeline
    end
  end
end
