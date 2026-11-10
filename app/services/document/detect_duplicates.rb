# Flags documents whose vector is a near-duplicate of +document+'s (GH #227, ADR 0014): KNN over Document vectors of
# +model+, every other document with cosine similarity at or above +threshold+ becomes a pending DocumentDuplicate.
# Exact copies never get here (one Document per checksum). Idempotent; confirmed and dismissed pairs are untouched.
#
#   Document::DetectDuplicates.call(document)  # => Result[flagged: 1]
class Document::DetectDuplicates
  Result = Data.define(:flagged)

  DEFAULT_THRESHOLD = 0.95
  NEIGHBORS = 20

  def self.call(document, model: LlmModels.embedding, threshold: self.threshold)
    new(document, model:, threshold:).call
  end

  # Minimum cosine similarity: Setting "document_dedup_threshold", then ENV DOCUMENT_DEDUP_THRESHOLD, then 0.95.
  def self.threshold
    Float(Setting.fetch("document_dedup_threshold") || ENV.fetch("DOCUMENT_DEDUP_THRESHOLD", DEFAULT_THRESHOLD))
  end

  def initialize(document, model:, threshold:)
    @document = document
    @model = model
    @threshold = threshold
  end

  def call
    embedding = @document.embeddings.find_by(model: @model)
    return Result.new(flagged: 0) unless embedding

    matches = neighbours(embedding)
    matches.each do |match|
      other = match.embeddable # : Document
      DocumentDuplicate.flag!(@document, other, similarity: 1 - match.neighbor_distance)
    end
    Result.new(flagged: matches.size)
  end

  private

  def neighbours(embedding)
    embedding.nearest_neighbors(:vector, distance: "cosine", threshold: 1 - @threshold)
             .where(embeddable_type: Document.polymorphic_name, model: @model, embeddable_id: Document.select(:id)) # steep:ignore
             .limit(NEIGHBORS)
             .includes(:embeddable)
  end
end
