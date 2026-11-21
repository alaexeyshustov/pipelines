module Orchestration
  class PipelineImportForm < ::BaseForm
    MAX_BYTES = 1.megabyte

    attr_reader :file, :pipelines

    validate :file_present
    validate :file_is_upload
    validate :file_within_size_limit
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
      @payload ||= JSON::Helpers.safe_parse(@file.read(MAX_BYTES + 1))
    end

    def file_present
      errors.add(:file, :blank) if @file.blank?
    end

    def file_is_upload
      return if @file.blank?
      return if @file.respond_to?(:read) && @file.respond_to?(:size)

      errors.add(:file, "is not an uploaded file")
    end

    def file_within_size_limit
      return if errors.include?(:file)
      return if @file.size <= MAX_BYTES

      errors.add(:file, "is too large (maximum #{MAX_BYTES / 1.megabyte} MB)")
    end

    def file_is_json_object
      return if errors.include?(:file)
      return if payload.is_a?(Hash)

      errors.add(:file, "is not valid JSON")
    end
  end
end
