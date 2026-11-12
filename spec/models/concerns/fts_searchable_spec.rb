require "rails_helper"

RSpec.describe FtsSearchable do
  describe "query handling" do
    it "matches a decomposed (NFD) query against composed text" do
      email = create(:email, body: "Besuch in München heute")
      expect(Email.fts_search("Mu\u0308nchen").map(&:record)).to eq([ email ])
    end

    it "matches non-ASCII letters, digits and underscores as whole terms" do
      email = create(:email, body: "Привет Straße 42 foo_bar")
      expect(Email.fts_search("Привет Straße 42 foo_bar").map(&:record)).to eq([ email ])
    end

    it "skips index rows whose record no longer exists" do
      Email.connection.execute("INSERT INTO emails_fts(rowid, subject, body, from_address) VALUES (999999, 'ghost', 'phantom', 'x')")
      expect(Email.fts_search("phantom")).to eq([])
    end
  end

  describe ".fts_search on a relation" do
    it "ignores a select on the relation when scoping" do
      kept = create(:email, subject: "kept", body: "salary one")
      expect(Email.select(:subject).where(id: kept.id).fts_search("salary").map { |match| match.record.id }).to eq([ kept.id ])
    end

    it "only returns matches inside the relation" do
      kept = create(:email, subject: "kept", body: "salary one")
      create(:email, subject: "dropped", body: "salary two")

      matches = Email.where(id: kept.id).fts_search("salary")

      expect(matches.map(&:record)).to eq([ kept ])
    end

    it "applies the limit after scoping" do
      create_list(:email, 3, body: "salary")
      scoped = create(:email, body: "salary")

      expect(Email.where(id: scoped.id).fts_search("salary", limit: 1).map(&:record)).to eq([ scoped ])
    end

    it "keeps preloads of the relation" do
      email = create(:email, body: "salary", interview: create(:interview))

      match = Email.includes(:interview).fts_search("salary").first

      expect(match.record.association(:interview)).to be_loaded
      expect(match.record.id).to eq(email.id)
    end
  end
end
