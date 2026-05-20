# frozen_string_literal: true

module Orchestration
  class PipelineRunForm
    include ActiveModel::Model

    attr_reader :pipeline_run

    validate :no_active_run
    validate :initial_input_valid

    def initialize(pipeline:, initial_input_params: nil)
      @pipeline = pipeline
      @initial_input_params = initial_input_params
    end

    def save
      return false unless valid?

      @pipeline_run = @pipeline.pipeline_runs.create(
        status: "pending",
        triggered_by: "manual",
        initial_input: extract_initial_input
      )
      @pipeline_run.persisted?
    end

    private

    def no_active_run
      return unless @pipeline.pipeline_runs.exists?(status: %w[pending running])

      errors.add(:base, "A run is already pending.")
    end

    def initial_input_valid
      return unless @pipeline.initial_input_schema.present?

      Orchestration::SchemaValidator.new(@pipeline.initial_input_schema).validate!(extract_initial_input)
    rescue Orchestration::SchemaValidator::Error => e
      errors.add(:base, e.message)
    end

    def extract_initial_input
      return nil if @pipeline.initial_input_schema.blank?

      @initial_input_params&.to_unsafe_h&.deep_stringify_keys
    end
  end
end
