# GH #226: one embedding per Email/Document and model (ADR 0014). +embeddings+ holds the bookkeeping (model, dimensions,
# content digest); the vectors live in the sqlite-vec table +embedding_vectors+, whose rowid is embeddings.id. vec0 is
# declared with +execute+ because the schema dumper does not know virtual tables. Dimensions are fixed per vec0 table
# (1024 = Embeddings::Client::DIMENSIONS); the partition keys make KNN filter by type and model inside the index.
class CreateEmbeddings < ActiveRecord::Migration[8.1]
  def up
    create_table :embeddings do |t|
      t.references :embeddable, polymorphic: true, null: false, index: false
      t.string :model, null: false
      t.integer :dimensions, null: false
      t.string :content_digest, null: false
      t.datetime :embedded_at, null: false
      t.timestamps
    end
    add_index :embeddings, %i[embeddable_type embeddable_id model], unique: true, name: "index_embeddings_on_embeddable_and_model"

    execute <<~SQL
      CREATE VIRTUAL TABLE embedding_vectors USING vec0(
        embeddable_type text partition key,
        model text partition key,
        embedding float[1024] distance_metric=cosine
      );
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS embedding_vectors"
    %w[info chunks rowids vector_chunks00].each { |suffix| execute "DROP TABLE IF EXISTS embedding_vectors_#{suffix}" }
    drop_table :embeddings
  end
end
