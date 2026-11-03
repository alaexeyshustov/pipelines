class CreateEmails < ActiveRecord::Migration[8.1]
  def up
    create_table :emails do |t|
      t.string :provider, null: false
      t.string :provider_message_id, null: false
      t.string :from_address, null: false
      t.string :to_address
      t.string :subject
      t.datetime :date, null: false
      t.text :body
      t.text :html_body
      t.string :source_url
      t.timestamps
      t.datetime :tagged_at # set once Tags::Classifier ran (GH #234)
      # which Interview the email fed (GH #228); emails survive an Interview being removed
      t.references :interview, foreign_key: { on_delete: :nullify }
    end
    add_index :emails, %i[provider provider_message_id], unique: true
    add_index :emails, :date

    # External-content FTS5 index: triggers keep it in sync for single and bulk writes.
    execute <<~SQL
      CREATE VIRTUAL TABLE emails_fts USING fts5(
        subject, body, from_address, content='emails', content_rowid='id'
      );
    SQL
    execute <<~SQL
      CREATE TRIGGER emails_fts_ai AFTER INSERT ON emails BEGIN
        INSERT INTO emails_fts(rowid, subject, body, from_address)
        VALUES (new.id, new.subject, new.body, new.from_address);
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER emails_fts_ad AFTER DELETE ON emails BEGIN
        INSERT INTO emails_fts(emails_fts, rowid, subject, body, from_address)
        VALUES ('delete', old.id, old.subject, old.body, old.from_address);
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER emails_fts_au AFTER UPDATE ON emails BEGIN
        INSERT INTO emails_fts(emails_fts, rowid, subject, body, from_address)
        VALUES ('delete', old.id, old.subject, old.body, old.from_address);
        INSERT INTO emails_fts(rowid, subject, body, from_address)
        VALUES (new.id, new.subject, new.body, new.from_address);
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS emails_fts_au"
    execute "DROP TRIGGER IF EXISTS emails_fts_ad"
    execute "DROP TRIGGER IF EXISTS emails_fts_ai"
    execute "DROP TABLE IF EXISTS emails_fts"
    drop_table :emails
  end
end
