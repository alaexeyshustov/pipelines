# frozen_string_literal: true

module Evaluation
  module Wizard
    class DatasetStepComponent < ViewComponent::Base
      def initialize(agent_name:, datasets:, draft_token:, selected_dataset_id: nil)
        @agent_name          = agent_name
        @datasets            = datasets
        @draft_token         = draft_token
        @selected_dataset_id = selected_dataset_id
      end

      def dataset_selected?(dataset)
        dataset.id.to_s == @selected_dataset_id.to_s && @selected_dataset_id.present?
      end

      def record_count(dataset)
        dataset.respond_to?(:record_count) ? dataset.record_count.to_i : 0
      end
    end
  end
end
