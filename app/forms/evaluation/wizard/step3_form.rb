
module Evaluation
  module Wizard
    class Step3Form < ::BaseForm
      validate :dataset_selected

      def initialize(draft_payload:, draft_token:)
        @payload     = draft_payload
        @draft_token = draft_token
      end

      def advance!(_payload) = true

      def agent_name          = @payload["agent_name"]
      def selected_dataset_id = @payload["dataset_id"]
      def draft_token         = @draft_token

      def datasets
        Evaluation::Dataset
          .for_agent(agent_name)
          .with_record_counts
      end

      private

      def dataset_selected
        errors.add(:dataset, "must be selected") if selected_dataset_id.blank?
      end
    end
  end
end
