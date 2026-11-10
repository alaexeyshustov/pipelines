# The vector of one Email or Document under one embedding model (ADR 0014). The row holds the bookkeeping (model,
# dimensions, digest of the embedded text) and the vector itself (float32 blob, see the neighbor gem); nearest-neighbour
# queries run in SQLite with sqlite-vec's cosine distance, filtered by type and model.
class Embedding < ApplicationRecord
  belongs_to :embeddable, polymorphic: true

  has_neighbors :vector, dimensions: Embeddings::Client::DIMENSIONS

  validates :model, :content_digest, presence: true

  class << self
    # Creates or replaces the embedding of +embeddable+ under +model+ (one upsert, no lookup, so storing a batch is
    # not an N+1).
    def store!(embeddable, model:, content_digest:, vector:)
      row = { embeddable_type: embeddable.class.polymorphic_name, embeddable_id: embeddable.id, model:, content_digest:,
              dimensions: vector.size, embedded_at: Time.current, vector: }
      new(row.except(:embeddable_type, :embeddable_id).merge(embeddable:)).validate! # upsert skips validations; uniqueness is the unique index's job
      stored = upsert(row, unique_by: :index_embeddings_on_embeddable_and_model, returning: column_names)
      instantiate(stored.first).tap { |embedding| embedding.embeddable = embeddable }
    end

    # The +limit+ embeddings of +type+ nearest to +vector+ under +model+, nearest first; +neighbor_distance+ is the cosine
    # distance (0 = same direction). The embeddables are preloaded.
    def nearest(vector, type:, model:, limit: 20)
      # select before nearest_neighbors, or neighbor selects every column (the 4 KB vectors included)
      where(embeddable_type: type, model:)
        .select(:id, :embeddable_type, :embeddable_id)
        .nearest_neighbors(:vector, vector, distance: "cosine")
        .limit(limit)
        .includes(:embeddable)
    end
  end
end
