module Orchestration
  class OutputKeyDeriver
    def initialize(action_name:, step:)
      @action_name = action_name
      @step = step
    end

    def derive
      base = @action_name.to_s.parameterize(separator: "_")
      base = "action" if base.blank?
      base = "x_#{base}" unless base.match?(/\A[a-z]/)

      unique_key(base)
    end

    private

    def unique_key(base)
      taken     = @step.step_actions.pluck(:output_key)
      candidate = base
      suffix    = 2
      while taken.include?(candidate)
        candidate = "#{base}_#{suffix}"
        suffix += 1
      end
      candidate
    end
  end
end
