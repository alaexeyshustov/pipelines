require "rails_helper"

RSpec.describe Tag do
  it "is valid with a name" do
    expect(build(:tag)).to be_valid
  end

  it_behaves_like "requires attribute", :name, :tag

  it "enforces a unique name" do
    create(:tag, name: "finance")
    expect(build(:tag, name: "finance")).not_to be_valid
  end

  it "lists the fixed top-level names" do
    expect(described_class::NAMES).to eq(%w[medical job_application child subscription bureaucracy finance])
  end

  describe ".seed_defaults!" do
    it "creates the fixed tags and starter subtags" do
      described_class.seed_defaults!
      expect(described_class.pluck(:name)).to match_array(described_class::NAMES)
      expect(described_class.find_by!(name: "finance").subtags.pluck(:name))
        .to match_array(%w[bank invoice tax insurance salary])
      expect(Subtag.where(name: "invoice").count).to eq(2)
    end

    it "is idempotent and keeps user-added subtags" do
      described_class.seed_defaults!
      described_class.find_by!(name: "child").subtags.create!(name: "sports")
      expect { described_class.seed_defaults! }.not_to(change { [ described_class.count, Subtag.count ] })
    end
  end
end
