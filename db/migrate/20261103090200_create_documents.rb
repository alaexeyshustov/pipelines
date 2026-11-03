class CreateDocuments < ActiveRecord::Migration[8.1]
  def up
    create_table :documents do |t|
      t.string :title, null: false
      t.string :mime_type, null: false
      t.text :text, null: false, default: ""
      t.string :checksum, null: false
      t.string :source, null: false
      t.string :source_url
      t.json :source_ref, null: false, default: {}
      t.references :email, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :documents, :checksum, unique: true

    # External-content FTS5 index: triggers keep it in sync for single and bulk writes.
    execute <<~SQL
      CREATE VIRTUAL TABLE documents_fts USING fts5(
        title, text, content='documents', content_rowid='id'
      );
    SQL
    execute <<~SQL
      CREATE TRIGGER documents_fts_ai AFTER INSERT ON documents BEGIN
        INSERT INTO documents_fts(rowid, title, text) VALUES (new.id, new.title, new.text);
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER documents_fts_ad AFTER DELETE ON documents BEGIN
        INSERT INTO documents_fts(documents_fts, rowid, title, text)
        VALUES ('delete', old.id, old.title, old.text);
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER documents_fts_au AFTER UPDATE ON documents BEGIN
        INSERT INTO documents_fts(documents_fts, rowid, title, text)
        VALUES ('delete', old.id, old.title, old.text);
        INSERT INTO documents_fts(rowid, title, text) VALUES (new.id, new.title, new.text);
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS documents_fts_au"
    execute "DROP TRIGGER IF EXISTS documents_fts_ad"
    execute "DROP TRIGGER IF EXISTS documents_fts_ai"
    execute "DROP TABLE IF EXISTS documents_fts"
    drop_table :documents
  end
end
