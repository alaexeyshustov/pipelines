require "rails_helper"

RSpec.describe FtsSearchable do
  describe ".fts_search on a relation" do
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
