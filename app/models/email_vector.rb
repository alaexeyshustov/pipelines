class EmailVector < ApplicationRecord
  self.table_name = "email_vectors"
  self.primary_key = "email_id"

  def self.upsert_embedding(email_id:, embedding:)
    connection.execute(
      "INSERT OR REPLACE INTO email_vectors(email_id, embedding) VALUES (?, ?)",
      [ email_id, serialize(embedding) ]
    )
  end

  def self.search(embedding, limit: 5)
    rows = connection.execute(
      "SELECT email_id, distance FROM email_vectors WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
      [ serialize(embedding), limit ]
    )

    rows.map { |row| { email_id: row[0], distance: row[1] } }
  end

  def self.serialize(embedding)
    embedding.pack("f*")
  end
  private_class_method :serialize
end
