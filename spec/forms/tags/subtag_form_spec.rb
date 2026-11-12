require "rails_helper"

RSpec.describe Tags::SubtagForm do
  let(:tag) { create(:tag) }

  it "creates a subtag under the tag" do
    form = described_class.new(tag:, name: "receipt")
    expect(form.save).to be(true)
    expect(form.subtag).to have_attributes(name: "receipt", tag:)
  end

  it "copies model errors for a duplicate name" do
    create(:subtag, tag:, name: "receipt")
    form = described_class.new(tag:, name: "receipt")
    expect(form.save).to be(false)
    expect(form.errors[:name]).not_to be_empty
  end

  it "requires a name" do
    expect(described_class.new(tag:, name: "").save).to be(false)
  end
end
