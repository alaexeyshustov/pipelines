require "rails_helper"
require "tmpdir"

RSpec.describe "db/structure.sql" do # rubocop:disable RSpec/DescribeClass
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "fresh.sqlite3") }
  let(:db) do
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "scratch", { adapter: "sqlite3", database: path })
    ActiveRecord::Tasks::DatabaseTasks.structure_load(config, Rails.root.join("db/structure.sql").to_s)
    SQLite3::Database.new(path).tap do |database|
      database.enable_load_extension(true)
      SqliteVec.load(database)
    end
  end

  after do
    db.close
    FileUtils.remove_entry(dir)
  end

  it "loads into a fresh database with a working vec0 table" do
    expect(db.execute("SELECT sql FROM sqlite_master WHERE name = 'embedding_vectors'").flatten.first).to include("USING vec0")
    expect(db.execute("SELECT count(*) FROM embedding_vectors")).to eq([ [ 0 ] ])
  end

  it "keeps the FTS5 sync triggers" do
    triggers = db.execute("SELECT name FROM sqlite_master WHERE type = 'trigger'").flatten
    expect(triggers).to include("emails_fts_ai", "emails_fts_au", "emails_fts_ad", "documents_fts_ai", "documents_fts_au", "documents_fts_ad")
  end
end
