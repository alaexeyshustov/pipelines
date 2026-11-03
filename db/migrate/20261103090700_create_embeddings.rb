# GH #226: one embedding per Email/Document and model (ADR 0014): the bookkeeping (model, dimensions, content digest)
# and the vector, a float32 blob read and queried through the neighbor gem (sqlite-vec's vec_distance_cosine).
class CreateEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :embeddings do |t|
      t.references :embeddable, polymorphic: true, null: false, index: false
      t.string :model, null: false
      t.integer :dimensions, null: false
      t.string :content_digest, null: false
      t.datetime :embedded_at, null: false
      t.timestamps
      t.binary :vector, null: false
    end
    add_index :embeddings, %i[embeddable_type embeddable_id model], unique: true, name: "index_embeddings_on_embeddable_and_model"
  end
end
