# The vector of one Email or Document under one embedding model (ADR 0014). The row holds the bookkeeping (model,
# dimensions, digest of the embedded text); the vector itself lives in the sqlite-vec table +embedding_vectors+
# (vec0, cosine distance, partitioned by type and model) under rowid = id.
class Embedding < ApplicationRecord
  Neighbor = Data.define(:embeddable, :distance)

  belongs_to :embeddable, polymorphic: true

  validates :model, :content_digest, presence: true
  validates :embeddable_id, uniqueness: { scope: %i[embeddable_type model] }

  after_destroy { self.class.delete_vectors(id) }

  # The stored vector, read back from the sqlite-vec table.
  def vector
    blob = self.class.connection.raw_connection.execute("SELECT embedding FROM embedding_vectors WHERE rowid = ?", [ id ]).dig(0, "embedding")
    blob.unpack("f*")
  end

  class << self
    # Creates or replaces the embedding of +embeddable+ under +model+.
    def store!(embeddable, model:, content_digest:, vector:)
      raise ArgumentError, "expected #{Embeddings::Client::DIMENSIONS} dimensions, got #{vector.size}" unless vector.size == Embeddings::Client::DIMENSIONS

      transaction do
        embedding = find_or_initialize_by(embeddable:, model:)
        embedding.update!(content_digest:, dimensions: vector.size, embedded_at: Time.current)
        index_vector(embedding, vector)
        embedding
      end
    end

    # The +limit+ items of +type+ nearest to +vector+ under +model+, nearest first.
    def nearest(vector, type:, model:, limit: 20)
      rows = connection.raw_connection.execute(
        "SELECT rowid, distance FROM embedding_vectors WHERE embedding MATCH ? AND k = ? AND embeddable_type = ? AND model = ?",
        [ pack(vector), limit, type, model ]
      )
      embeddings = includes(:embeddable).where(id: rows.pluck("rowid")).index_by(&:id)
      rows.map { |row| Neighbor.new(embeddable: embeddings.fetch(row["rowid"]).embeddable, distance: row["distance"]) }
    end

    # Deletes the embeddings and vectors of every model but +model+ (after a re-embed).
    def purge_except!(model)
      transaction do
        connection.raw_connection.execute("DELETE FROM embedding_vectors WHERE model != ?", [ model ])
        where.not(model:).delete_all
      end
    end

    def delete_vectors(id)
      connection.raw_connection.execute("DELETE FROM embedding_vectors WHERE rowid = ?", [ id ])
    end

    private

    def index_vector(embedding, vector)
      delete_vectors(embedding.id)
      connection.raw_connection.execute(
        "INSERT INTO embedding_vectors(rowid, embeddable_type, model, embedding) VALUES (?, ?, ?, ?)",
        [ embedding.id, embedding.embeddable_type, embedding.model, pack(vector) ]
      )
    end

    def pack(vector) = vector.pack("f*")
  end
end
