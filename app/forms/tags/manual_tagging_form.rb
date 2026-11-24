module Tags
  # Adds (or edits) a +source: manual+ tagging. An existing llm tagging for the same tag becomes manual, so
  # re-tagging by the classifier no longer touches it.
  class ManualTaggingForm < ::BaseForm
    attribute :tag_id, :integer
    attribute :subtag_id, :integer

    def initialize(taggable:, tag_id: nil, subtag_id: nil)
      super(tag_id:, subtag_id: subtag_id.presence)
      @taggable = taggable
    end

    def save
      tag = Tag.find_by(id: tag_id)
      return fail_with(:tag, "must exist") unless tag

      tagging = @taggable.taggings.find_or_initialize_by(tag:)
      tagging.assign_attributes(subtag: (Subtag.find_by(id: subtag_id) if subtag_id), source: "manual", confidence: nil)
      return true if save_tagging(tagging)

      tagging.errors.each { |error| errors.add(error.attribute, error.message) }
      false
    end

    private

    # The tagging and the status change together: a manually tagged record counts as tagged, so the next ingestion
    # run embeds it and ingests its attachments. Removing a manual tag leaves the status alone.
    def save_tagging(tagging)
      Tagging.transaction do
        tagging.save && @taggable.update!(classification_status: "tagged")
      end
    end

    def fail_with(attribute, message)
      errors.add(attribute, message)
      false
    end
  end
end
