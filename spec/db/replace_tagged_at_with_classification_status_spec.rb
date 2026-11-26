require "rails_helper"

# Assumes the planned migration db/migrate/<timestamp>_replace_tagged_at_with_classification_status.rb defining
# ReplaceTaggedAtWithClassificationStatus (GH #248). The timestamp is unknown until it is written, so the file is globbed.
CLASSIFICATION_STATUS_MIGRATION_FILE = Dir[Rails.root.join("db/migrate/*_replace_tagged_at_with_classification_status.rb").to_s].first
require CLASSIFICATION_STATUS_MIGRATION_FILE if CLASSIFICATION_STATUS_MIGRATION_FILE

RSpec.describe "ReplaceTaggedAtWithClassificationStatus migration", prosopite: false do # rubocop:disable RSpec/DescribeClass
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration_class) do
    raise "db/migrate/*_replace_tagged_at_with_classification_status.rb does not exist yet" unless CLASSIFICATION_STATUS_MIGRATION_FILE

    ReplaceTaggedAtWithClassificationStatus
  end
  let(:triggers) do
    %w[emails_fts_ai emails_fts_au emails_fts_ad documents_fts_ai documents_fts_au documents_fts_ad]
  end

  def run_migration(direction)
    ActiveRecord::Migration.suppress_messages { migration_class.new.migrate(direction) }
    [ Email, Document ].each(&:reset_column_information)
  end

  def column_names(table) = connection.columns(table).map(&:name)

  def trigger_names = connection.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger'")

  def index_names(table) = connection.select_values("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = '#{table}'")

  def insert_email(tagged_at:, subject: "Interview invitation")
    stamp = tagged_at ? connection.quote(tagged_at) : "NULL"
    connection.execute(<<~SQL.squish)
      INSERT INTO emails (provider, provider_message_id, from_address, subject, date, body, tagged_at, created_at, updated_at)
      VALUES ('gmail', 'm#{SecureRandom.hex(4)}', 'a@b.com', #{connection.quote(subject)}, CURRENT_TIMESTAMP, 'body', #{stamp},
              CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    connection.select_value("SELECT last_insert_rowid()")
  end

  def insert_document(tagged_at:, title: "Lease agreement")
    stamp = tagged_at ? connection.quote(tagged_at) : "NULL"
    connection.execute(<<~SQL.squish)
      INSERT INTO documents (title, mime_type, text, checksum, source, tagged_at, created_at, updated_at)
      VALUES (#{connection.quote(title)}, 'application/pdf', 'text', 'sha#{SecureRandom.hex(4)}', 'drive', #{stamp},
              CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    connection.select_value("SELECT last_insert_rowid()")
  end

  # Bring the schema back to its pre-migration shape so up has something to do.
  before { run_migration(:down) if column_names("emails").include?("classification_status") }

  describe "up" do
    it "adds classification_status (string, not null, default pending) and drops tagged_at on both tables" do
      run_migration(:up)

      %w[emails documents].each do |table|
        status = connection.columns(table).find { |c| c.name == "classification_status" }
        expect(status).to have_attributes(null: false, default: "pending")
        expect(column_names(table)).not_to include("tagged_at")
      end
    end

    it "adds (provider, classification_status) on emails and (classification_status) on documents" do
      run_migration(:up)

      expect(connection.indexes("emails").map(&:columns)).to include(%w[provider classification_status])
      expect(connection.indexes("documents").map(&:columns)).to include(%w[classification_status])
    end

    it "keeps all six FTS triggers" do
      run_migration(:up)

      expect(trigger_names).to include(*triggers)
    end

    it "keeps full-text search working for rows that existed before" do
      email_id = insert_email(tagged_at: nil, subject: "Zebrafish invitation")
      document_id = insert_document(tagged_at: nil, title: "Zebrafish lease")

      run_migration(:up)

      expect(connection.select_values("SELECT rowid FROM emails_fts WHERE emails_fts MATCH 'zebrafish'")).to eq([ email_id ])
      expect(connection.select_values("SELECT rowid FROM documents_fts WHERE documents_fts MATCH 'zebrafish'")).to eq([ document_id ])
    end

    it "keeps indexing rows inserted afterwards" do
      run_migration(:up)

      id = connection.insert(<<~SQL.squish)
        INSERT INTO emails (provider, provider_message_id, from_address, subject, date, body, created_at, updated_at)
        VALUES ('gmail', 'late', 'a@b.com', 'Quokka news', CURRENT_TIMESTAMP, 'b', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL

      expect(connection.select_values("SELECT rowid FROM emails_fts WHERE emails_fts MATCH 'quokka'")).to eq([ id ])
    end

    it "succeeds on empty tables" do
      expect { run_migration(:up) }.not_to raise_error
    end
  end

  describe "down" do
    it "restores a nullable tagged_at and removes classification_status", :aggregate_failures do
      run_migration(:up)

      run_migration(:down)

      %w[emails documents].each do |table|
        expect(column_names(table)).to include("tagged_at")
        expect(column_names(table)).not_to include("classification_status")
      end
    end

    it "drops the new indexes and keeps all six FTS triggers" do
      run_migration(:up)

      run_migration(:down)

      expect(index_names("emails")).not_to include(a_string_matching(/classification_status/))
      expect(index_names("documents")).not_to include(a_string_matching(/classification_status/))
      expect(trigger_names).to include(*triggers)
    end
  end
end
