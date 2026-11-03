# GH #227: candidate pairs of semantically near-identical Documents. A pair is stored once in canonical order
# (document_id < duplicate_id) so re-runs are idempotent; the user confirms or dismisses it (status).
class CreateDocumentDuplicates < ActiveRecord::Migration[8.1]
  def change
    create_table :document_duplicates do |t|
      t.references :document, null: false, foreign_key: true, index: false
      t.references :duplicate, null: false, foreign_key: { to_table: :documents }
      t.float :similarity, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    add_index :document_duplicates, %i[document_id duplicate_id], unique: true
  end
end
