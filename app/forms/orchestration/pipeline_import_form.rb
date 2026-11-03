module Orchestration
  class PipelineImportForm < ::BaseForm
    attr_reader :file, :pipelines

    validate :file_present
    validate :file_is_json_object

    def initialize(file:)
      @file = file
      @pipelines = []
    end

    def save
      return false unless valid?

      result = Orchestration::PipelineImporter.call(payload)
      result.errors.each { |message| errors.add(:base, message) }
      return false if errors.any?

      @pipelines = result.pipelines
      true
    end

    private

    def payload
      @payload ||= JSON::Helpers.safe_parse(@file.read)
    end

    def file_present
      errors.add(:file, :blank) if @file.blank?
    end

    def file_is_json_object
      return if @file.blank?
      return if payload.is_a?(Hash)

      errors.add(:file, "is not valid JSON")
    end
  end
end
