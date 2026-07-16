module Evaluation
  module Wizard
    class StepNavComponent < ViewComponent::Base
      STEPS = [ "Agent & Prompt", "Metrics", "Dataset", "Review & Run" ].freeze

      def initialize(current_step:)
        @current_step = current_step
      end

      def step_state(index)
        step_number = index + 1
        if step_number < @current_step
          :complete
        elsif step_number == @current_step
          :active
        else
          :upcoming
        end
      end

      def step_label(index)
        STEPS[index]
      end

      def steps
        Array.new(STEPS.length) { |i| { label: step_label(i), state: step_state(i) } }
      end
    end
  end
end
