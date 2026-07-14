# frozen_string_literal: true

module Evaluation
  class ImproveFailureLogger
    def self.call(context:, experiment:, error:)
      new(context: context, experiment: experiment, error: error).call
    end

    def initialize(context:, experiment:, error:)
      @context = context
      @experiment = experiment
      @error = error
    end

    def call
      Rails.logger.error("#{@context} for experiment #{@experiment.id}: #{@error.message}")
    end
  end
end
