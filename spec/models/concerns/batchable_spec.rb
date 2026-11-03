require "rails_helper"

RSpec.describe Batchable do
  describe ".destroy_by_ids" do
    let!(:kept)     { create(:interview) }
    let!(:doomed)   { create(:interview) }
    let!(:doomed_b) { create(:interview) }

    it "destroys exactly the records with the given ids" do
      Interview.destroy_by_ids([ doomed.id, doomed_b.id ])

      expect(Interview.exists?(doomed.id)).to be false
      expect(Interview.exists?(doomed_b.id)).to be false
    end

    it "leaves other records untouched" do
      Interview.destroy_by_ids([ doomed.id, doomed_b.id ])

      expect(Interview.all).to contain_exactly(kept)
    end

    it "destroys nothing when given no ids" do
      expect { Interview.destroy_by_ids([]) }.not_to change(Interview, :count)
    end
  end
end
