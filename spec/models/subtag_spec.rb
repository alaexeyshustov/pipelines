require "rails_helper"

RSpec.describe Subtag do
  it "is valid with a tag and a name" do
    expect(build(:subtag)).to be_valid
  end

  it_behaves_like "requires attribute", :name, :subtag

  it "rejects a duplicate name under the same tag" do
    tag = create(:tag)
    create(:subtag, tag:, name: "invoice")
    expect(build(:subtag, tag:, name: "invoice")).not_to be_valid
  end

  it "allows the same name under different tags" do
    create(:subtag, name: "invoice")
    expect(build(:subtag, name: "invoice")).to be_valid
  end

  it "enforces per-parent uniqueness in the database" do
    tag = create(:tag)
    create(:subtag, tag:, name: "invoice")
    expect { build(:subtag, tag:, name: "invoice").save!(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
