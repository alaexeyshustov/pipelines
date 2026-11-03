# Embeds Emails and Documents (ADR 0014): one batched model call for the records whose text digest differs from
# the stored embedding of +model+. Unchanged records cost nothing; records without text are skipped.
#
#   Embeddings::Embed.call([ email ])  # => Result[embedded: 1, unchanged: 0, skipped: 0]
class Embeddings::Embed
  Result = Data.define(:embedded, :unchanged, :skipped)
  Pending = Data.define(:record, :text, :digest)

  def self.call(records, model: LlmModels.embedding)
    new(records, model:).call
  end

  def initialize(records, model:)
    @records = records
    @model = model
  end

  def call
    pending, skipped = candidates.partition { |candidate| candidate.text.present? }
    stale = pending.select { |candidate| stale?(candidate) }
    store(stale)
    Result.new(embedded: stale.size, unchanged: pending.size - stale.size, skipped: skipped.size)
  end

  private

  def candidates
    @records.map do |record|
      text = Embeddings::Text.for(record)
      Pending.new(record:, text:, digest: Digest::SHA256.hexdigest(text))
    end
  end

  def stale?(candidate)
    candidate.record.embeddings.find_by(model: @model)&.content_digest != candidate.digest
  end

  def store(stale)
    vectors = Embeddings::Client.documents(stale.map(&:text), model: @model)
    stale.each_with_index do |candidate, index|
      Embedding.store!(candidate.record, model: @model, content_digest: candidate.digest, vector: vectors.fetch(index))
    end
  end
end
