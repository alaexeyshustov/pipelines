
module Evaluation
  module Wizard
    class Step1Form < ::BaseForm
      def initialize(draft_payload:)
        @payload = draft_payload
      end

      def advance!(_payload) = true

      def agent_names      = Evaluation::Prompt.distinct.pluck(:name).sort
      def prompts          = Evaluation::Prompt.order(version: :desc)
      def agent_name       = @payload["agent_name"]
      def prompt_id        = @payload["prompt_id"]
      def experiment_name  = @payload["experiment_name"]
      def sample_model     = @payload["sample_model"]
      def evaluation_model = @payload["evaluation_model"]
      def available_models = Orchestration::Agent.available_models
    end
  end
end
