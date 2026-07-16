
module Evaluation
  module Wizard
    class StepNavComponentPreview < ViewComponent::Preview
      # @param current_step number
      def default(current_step: 1)
        render(Evaluation::Wizard::StepNavComponent.new(current_step: current_step.to_i))
      end

      def step_two
        render(Evaluation::Wizard::StepNavComponent.new(current_step: 2))
      end

      def step_four
        render(Evaluation::Wizard::StepNavComponent.new(current_step: 4))
      end
    end
  end
end
