require "rails_helper"

RSpec.describe Tags::ManualTaggingForm do
  let(:email) { create(:email) }
  let(:tag) { create(:tag) }
  let(:subtag) { create(:subtag, tag:) }

  it "adds a manual tagging with a subtag" do
    form = described_class.new(taggable: email, tag_id: tag.id, subtag_id: subtag.id)
    expect(form.save).to be(true)
    expect(email.taggings.last).to have_attributes(tag:, subtag:, source: "manual", confidence: nil)
  end

  it "adds a tag without a subtag" do
    expect(described_class.new(taggable: email, tag_id: tag.id, subtag_id: "").save).to be(true)
    expect(email.taggings.last.subtag).to be_nil
  end

  it "turns an existing llm tagging for the tag into a manual one" do
    create(:tagging, taggable: email, tag:, source: "llm", confidence: 0.8)
    expect(described_class.new(taggable: email, tag_id: tag.id, subtag_id: subtag.id).save).to be(true)
    expect(email.taggings.count).to eq(1)
    expect(email.taggings.last).to have_attributes(source: "manual", subtag:, confidence: nil)
  end

  it "rejects a subtag of another tag" do
    other = create(:subtag)
    form = described_class.new(taggable: email, tag_id: tag.id, subtag_id: other.id)
    expect(form.save).to be(false)
    expect(form.errors[:subtag]).not_to be_empty
  end

  it "requires an existing tag" do
    form = described_class.new(taggable: email, tag_id: "0", subtag_id: nil)
    expect(form.save).to be(false)
    expect(form.errors[:tag]).not_to be_empty
  end

  %w[pending untagged failed].each do |status|
    it "sets a #{status} email to tagged on save" do
      email.update!(classification_status: status)

      described_class.new(taggable: email, tag_id: tag.id, subtag_id: nil).save

      expect(email.reload).to be_tagged
    end
  end

  it "sets a pending document to tagged on save" do
    document = create(:document, classification_status: "pending")

    described_class.new(taggable: document, tag_id: tag.id, subtag_id: nil).save

    expect(document.reload).to be_tagged
  end

  it "keeps the status when the save fails" do
    email.update!(classification_status: "untagged")
    other = create(:subtag)

    described_class.new(taggable: email, tag_id: tag.id, subtag_id: other.id).save

    expect(email.reload).to be_untagged
  end

  it "keeps the status when the tag does not exist" do
    described_class.new(taggable: email, tag_id: "0", subtag_id: nil).save

    expect(email.reload).to be_pending
  end
end
