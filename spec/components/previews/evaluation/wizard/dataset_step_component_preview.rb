# frozen_string_literal: true

module Evaluation
  module Wizard
    class DatasetStepComponentPreview < ViewComponent::Preview
      def default
        datasets = [
          Evaluation::Dataset.new(id: 1, name: "Production Emails"),
          Evaluation::Dataset.new(id: 2, name: "Test Subset")
        ]
        form = OpenStruct.new(
          agent_name: "ClassifyAgent",
          datasets: datasets,
          draft_token: "abc123",
          selected_dataset_id: 1
        )
        render(Evaluation::Wizard::DatasetStepComponent.new(form: form))
      end

      def none_selected
        form = OpenStruct.new(
          agent_name: "ClassifyAgent",
          datasets: [],
          draft_token: "abc123",
          selected_dataset_id: nil
        )
        render(Evaluation::Wizard::DatasetStepComponent.new(form: form))
      end
    end
  end
end
