require "rails_helper"

RSpec.describe Email do
  def indexed(term)
    described_class.connection.select_values("SELECT rowid FROM emails_fts WHERE emails_fts MATCH '#{term}'")
  end

  describe "validations" do
    it "requires provider, message id, from and date" do
      email = described_class.new
      email.validate
      expect(email.errors.attribute_names).to include(:provider, :provider_message_id, :from_address, :date)
    end

    it "limits provider to gmail and yahoo" do
      expect(build(:email, provider: "aol")).not_to be_valid
    end

    it "keeps the message id unique per provider" do
      create(:email, provider: "gmail", provider_message_id: "m1")
      expect(build(:email, provider: "gmail", provider_message_id: "m1")).not_to be_valid
      expect(build(:email, provider: "yahoo", provider_message_id: "m1")).to be_valid
    end

    it "enforces uniqueness in the database too" do
      create(:email, provider: "gmail", provider_message_id: "m1")
      dup = build(:email, provider: "gmail", provider_message_id: "m1")
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "tagging" do
    it "has tags through taggings, removed with the email" do
      email = create(:email)
      tag = create(:tag, name: "job_application")
      Tagging.create!(taggable: email, tag:, source: "llm")
      expect(email.tags).to eq([ tag ])
      expect { email.destroy! }.to change(Tagging, :count).by(-1)
    end
  end

  describe "FTS5 index" do
    it "indexes on insert" do
      email = create(:email, subject: "Interview invitation", body: "Let us chat")
      expect(indexed("interview")).to eq([ email.id ])
      expect(indexed("chat")).to eq([ email.id ])
    end

    it "indexes the sender" do
      email = create(:email, from_address: "jane@initech.com")
      expect(indexed("initech")).to eq([ email.id ])
    end

    it "reindexes on update" do
      email = create(:email, subject: "Interview invitation")
      email.update!(subject: "Rejection notice")
      expect(indexed("interview")).to be_empty
      expect(indexed("rejection")).to eq([ email.id ])
    end

    it "removes from the index on destroy" do
      email = create(:email, subject: "Interview invitation")
      email.destroy!
      expect(indexed("interview")).to be_empty
    end

    it "stays consistent through bulk writes" do
      create(:email, subject: "Offer letter")
      described_class.where(subject: "Offer letter").update_all(subject: "Declined")
      expect(indexed("offer")).to be_empty
      expect(indexed("declined").size).to eq(1)
      described_class.delete_all
      expect(indexed("declined")).to be_empty
    end

    it "passes the FTS5 integrity check" do
      create(:email)
      expect { described_class.connection.execute("INSERT INTO emails_fts(emails_fts, rank) VALUES('integrity-check', 1)") }
        .not_to raise_error
    end
  end

  describe "#tagged_at" do
    it "is nil by default and can be set" do
      email = create(:email)
      expect(email.tagged_at).to be_nil
      email.update!(tagged_at: Time.zone.now)
      expect(email.reload.tagged_at).not_to be_nil
    end
  end

  describe ".backfill_days" do
    it "defaults to 90" do
      expect(described_class.backfill_days).to eq(90)
    end

    it "is overridable through the email_backfill_days setting" do
      Setting.set("email_backfill_days", "30")
      expect(described_class.backfill_days).to eq(30)
    end

    it "falls back to ENV when no setting exists" do
      stub_const("ENV", ENV.to_h.merge("EMAIL_BACKFILL_DAYS" => "14"))
      expect(described_class.backfill_days).to eq(14)
    end
  end
end
