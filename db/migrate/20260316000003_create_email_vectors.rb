class CreateEmailVectors < ActiveRecord::Migration[8.1]
  def up
    # sqlite-vec virtual table for storing email embeddings (1536 dimensions, OpenAI default)
    execute <<~SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS email_vectors USING vec0(
        email_id TEXT PRIMARY KEY,
        embedding FLOAT[1536]
      );
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS email_vectors;"
  end
end
