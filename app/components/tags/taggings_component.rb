module Tags
  # The tags on an Email or Document, with manual add/remove controls. Callers pass loaded data.
  class TaggingsComponent < ViewComponent::Base
    def initialize(taggings:, tags:, base_url:, errors: nil)
      @taggings = taggings
      @tags = tags
      @base_url = base_url
      @errors = errors
    end

    private

    attr_reader :taggings, :tags, :base_url, :errors

    def remove_url(tagging) = "#{base_url}/#{tagging.id}"

    def label(tagging)
      [ tagging.tag.name, tagging.subtag&.name ].compact.join(" / ")
    end

    def origin(tagging)
      return "manual" unless tagging.source == "llm"

      tagging.confidence ? "llm #{(tagging.confidence * 100).round}%" : "llm"
    end

    def tag_options = tags.map { |tag| [ tag.name, tag.id ] }

    def subtag_options
      tags.flat_map { |tag| tag.subtags.sort_by(&:name).map { |subtag| [ "#{tag.name} / #{subtag.name}", subtag.id ] } }
    end
  end
end
