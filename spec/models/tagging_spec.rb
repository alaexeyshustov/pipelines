require "rails_helper"

RSpec.describe Tagging do
  it "is valid with a taggable and tag" do
    expect(build(:tagging)).to be_valid
  end

  it "allows an optional subtag of the same tag and a nil confidence" do
    tag = create(:tag)
    tagging = build(:tagging, tag:, subtag: create(:subtag, tag:), source: "llm", confidence: nil)
    expect(tagging).to be_valid
  end

  it "rejects a subtag from another tag" do
    tagging = build(:tagging, subtag: create(:subtag))
    expect(tagging).not_to be_valid
    expect(tagging.errors[:subtag]).not_to be_empty
  end

  it "rejects an unknown source" do
    expect(build(:tagging, source: "robot")).not_to be_valid
  end

  it "allows several different tags on one taggable" do
    mail = create(:application_mail)
    create(:tagging, taggable: mail)
    expect(build(:tagging, taggable: mail)).to be_valid
  end

  it "rejects the same tag twice on one taggable" do
    existing = create(:tagging)
    duplicate = build(:tagging, taggable: existing.taggable, tag: existing.tag)
    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
