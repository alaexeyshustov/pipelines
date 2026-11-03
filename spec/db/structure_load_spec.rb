require "rails_helper"
require "tmpdir"

RSpec.describe "db/structure.sql" do # rubocop:disable RSpec/DescribeClass
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "fresh.sqlite3") }
  let(:db) do
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "scratch", { adapter: "sqlite3", database: path })
    ActiveRecord::Tasks::DatabaseTasks.structure_load(config, Rails.root.join("db/structure.sql").to_s)
    SQLite3::Database.new(path)
  end

  after do
    db.close
    FileUtils.remove_entry(dir)
  end

  it "loads into a fresh database without the sqlite-vec extension, with the vector on embeddings" do
    vector = db.execute("PRAGMA table_info(embeddings)").find { |column| column[1] == "vector" }
    expect(vector.values_at(2, 3)).to eq([ "BLOB", 1 ])
    expect(db.execute("SELECT name FROM sqlite_master WHERE name LIKE 'embedding_vectors%'")).to be_empty
  end

  it "keeps the FTS5 sync triggers" do
    triggers = db.execute("SELECT name FROM sqlite_master WHERE type = 'trigger'").flatten
    expect(triggers).to include("emails_fts_ai", "emails_fts_au", "emails_fts_ad", "documents_fts_ai", "documents_fts_au", "documents_fts_ad")
  end
end
