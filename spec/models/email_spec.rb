require "rails_helper"

RSpec.describe Email do
  def indexed(term)
    described_class.connection.select_values("SELECT rowid FROM emails_fts WHERE emails_fts MATCH '#{term}'")
  end

  describe "interview" do
    it "is optional" do
      expect(build(:email, interview: nil)).to be_valid
    end

    it "is listed on the interview's emails" do
      interview = create(:interview)
      email = create(:email, interview: interview)
      expect(interview.emails).to contain_exactly(email)
    end

    it "keeps the email, with a nil interview_id, when the interview is destroyed" do
      interview = create(:interview)
      email = create(:email, interview: interview)
      interview.destroy!
      expect(email.reload.interview_id).to be_nil
    end
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

  describe ".awaiting_tagging" do
    it "returns pending and failed emails stored before the cutoff" do
      pending_email = create(:email, created_at: 2.hours.ago, classification_status: "pending")
      failed_email = create(:email, created_at: 2.hours.ago, classification_status: "failed")
      create(:email, created_at: 2.hours.ago, classification_status: "tagged")
      create(:email, created_at: 2.hours.ago, classification_status: "untagged")
      create(:email, created_at: 5.minutes.ago, classification_status: "pending")

      expect(described_class.awaiting_tagging(before: 1.hour.ago)).to contain_exactly(pending_email, failed_email)
    end
  end

  describe ".without_embedding" do
    include EmbeddingHelpers

    it "returns the emails with no embedding for the model, whatever the digest of other models" do
      embedded = create(:email)
      other_model = create(:email)
      bare = create(:email)
      embed_as(embedded, unit_vector(0), model: "m1")
      embed_as(other_model, unit_vector(1), model: "m2")

      expect(described_class.without_embedding(model: "m1")).to contain_exactly(other_model, bare)
    end

    it "composes with other scopes" do
      tagged = create(:email, classification_status: "tagged")
      create(:email, classification_status: "pending")

      expect(described_class.tagged.without_embedding(model: "m1")).to eq([ tagged ])
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

    it "keeps the index intact when only classification_status changes" do
      email = create(:email, subject: "Interview invitation")
      email.update!(classification_status: "tagged")
      expect(indexed("interview")).to eq([ email.id ])
      expect { described_class.connection.execute("INSERT INTO emails_fts(emails_fts, rank) VALUES('integrity-check', 1)") }
        .not_to raise_error
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

  describe "#classification_status" do
    it "is pending by default" do
      expect(create(:email).reload).to be_pending
    end

    it "is an enum of pending, tagged, untagged and failed with unprefixed predicates and scopes" do
      expect(described_class.classification_statuses).to eq(
        "pending" => "pending", "tagged" => "tagged", "untagged" => "untagged", "failed" => "failed"
      )
      email = create(:email, classification_status: "untagged")
      expect(email).to be_untagged
      expect(described_class.untagged).to eq([ email ])
    end

    it "rejects an unknown value with a validation error" do
      email = build(:email, classification_status: "bogus")

      expect(email).not_to be_valid
      expect(email.errors[:classification_status]).to be_present
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
