
module Evaluation
  module Wizard
    class ReviewStepComponentPreview < ViewComponent::Preview
      def default
        prompt  = Evaluation::Prompt.new(id: 1, name: "ClassifyAgent", version: 3,
                                         system_prompt: "You are a classifier.",
                                         user_prompt: "Classify: {{input}}")
        dataset = Evaluation::Dataset.new(id: 1, name: "Production Emails")
        form = OpenStruct.new(
          agent_name: "ClassifyAgent",
          prompt: prompt,
          experiment_name: "My Experiment",
          metrics_count: 3,
          dataset: dataset
        )
        render(Evaluation::Wizard::ReviewStepComponent.new(form: form))
      end

      def missing_selections
        form = OpenStruct.new(
          agent_name: "ClassifyAgent",
          prompt: nil,
          experiment_name: nil,
          metrics_count: 0,
          dataset: nil
        )
        render(Evaluation::Wizard::ReviewStepComponent.new(form: form))
      end
    end
  end
end
