module Evaluation
  class ImproveFailureLogger
    Result = Data.define(:message)

    def self.call(context:, experiment:, error:)
      new(context: context, experiment: experiment, error: error).call
    end

    def initialize(context:, experiment:, error:)
      @context = context
      @experiment = experiment
      @error = error
    end

    def call
      message = "#{@context} for experiment #{@experiment.id}: #{@error.message}"
      Rails.logger.error(message)
      Result.new(message:)
    end
  end
end
