# frozen_string_literal: true

module Orchestration
  class OutputKeyDeriver
    def self.call(action_name:, step:)
      new(action_name: action_name, step: step).call
    end

    def initialize(action_name:, step:)
      @action_name = action_name
      @step = step
    end

    def call
      base = @action_name.to_s.parameterize(separator: "_")
      base = "action" if base.blank?
      base = "x_#{base}" unless base.match?(/\A[a-z]/)

      candidate = base
      suffix    = 2
      while @step.step_actions.where(output_key: candidate).exists?
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end
      candidate
    end
  end
end
