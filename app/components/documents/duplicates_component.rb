module Documents
  # Duplicate candidates of a Document, each with a link to the other document, the similarity and confirm/dismiss
  # buttons. Callers pass the pairs with both documents loaded.
  class DuplicatesComponent < ViewComponent::Base
    def initialize(document:, duplicates:)
      @document = document
      @duplicates = duplicates
    end

    def render? = duplicates.any?

    private

    attr_reader :document, :duplicates

    def similarity(duplicate) = "#{(duplicate.similarity * 100).round(1)}%"

    def url(duplicate, action) = send(:"#{action}_document_duplicate_path", document, duplicate)
  end
end
