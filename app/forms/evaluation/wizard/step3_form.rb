# frozen_string_literal: true

module Evaluation
  module Wizard
    class Step3Form
      def initialize(draft_payload:, draft_token:)
        @payload     = draft_payload
        @draft_token = draft_token
      end

      def agent_name          = @payload["agent_name"]
      def selected_dataset_id = @payload["dataset_id"]
      def draft_token         = @draft_token

      def datasets
        Evaluation::Dataset
          .left_joins(:dataset_samples)
          .group("evaluation_datasets.id")
          .select("evaluation_datasets.*, COUNT(evaluation_dataset_samples.id) AS record_count")
          .order(:name)
      end
    end
  end
end
