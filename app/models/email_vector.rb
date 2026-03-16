# Wraps the sqlite-vec virtual table for email embeddings.
# Use EmailVector.search to find semantically similar emails.
class EmailVector < ApplicationRecord
  self.table_name = "email_vectors"
  self.primary_key = "email_id"

  # Store a float array embedding for an email.
  def self.upsert_embedding(email_id:, embedding:)
    connection.execute(
      "INSERT OR REPLACE INTO email_vectors(email_id, embedding) VALUES (?, ?)",
      [ email_id, SqliteVec.serialize_float32(embedding) ]
    )
  end

  # Find the top-k most similar emails to the given query embedding.
  # Returns an array of { email_id:, distance: } hashes.
  def self.search(embedding, limit: 5)
    rows = connection.execute(
      "SELECT email_id, distance FROM email_vectors WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
      [ SqliteVec.serialize_float32(embedding), limit ]
    )
    rows.map { |row| { email_id: row[0], distance: row[1] } }
  end
end
