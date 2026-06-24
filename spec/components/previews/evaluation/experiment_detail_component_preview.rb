# frozen_string_literal: true

module Evaluation
  class ExperimentDetailComponentPreview < ViewComponent::Preview
    def default
      dataset  = Evaluation::Dataset.new(id: 1, name: "Sample Dataset")
      prompt   = Evaluation::Prompt.new(id: 1, name: "ClassifyAgent", version: 2,
                                        system_prompt: "You are a classifier.",
                                        user_prompt: "Classify: {{input}}",
                                        output_schema: {})
      experiment = Evaluation::Experiment.new(id: 1, name: "Experiment #1",
                                              dataset: dataset, prompt: prompt)
      render(Evaluation::ExperimentDetailComponent.new(experiment: experiment))
    end
  end
end
