# frozen_string_literal: true

module Evaluation
  module Wizard
    class DatasetStepComponent < ViewComponent::Base
      def initialize(form:)
        @form = form
      end

      def agent_name          = @form.agent_name
      def datasets            = @form.datasets
      def draft_token         = @form.draft_token
      def selected_dataset_id = @form.selected_dataset_id

      def dataset_selected?(dataset)
        dataset.id.to_s == selected_dataset_id.to_s && selected_dataset_id.present?
      end

      def record_count(dataset)
        dataset.respond_to?(:record_count) ? dataset.record_count.to_i : 0
      end
    end
  end
end
