
require "rails_helper"

RSpec.describe Interviews::BatchService do
  describe "#call" do
    context "when action is delete" do
      it "destroys exactly the selected records and leaves others untouched" do
        doomed = create_list(:interview, 2)
        kept   = create(:interview, company: "Kept Corp")

        result = described_class.new(ids: doomed.map(&:id), batch_action: "delete").call

        expect(result.ok?).to be true
        expect(result.message).to eq("Deleted 2 record(s).")
        expect(Interview.all).to contain_exactly(kept)
      end
    end

    context "when no ids are provided" do
      it "returns a failure result" do
        result = described_class.new(ids: [], batch_action: "delete").call

        expect(result.ok?).to be false
        expect(result.message).to eq("No records selected.")
      end
    end
  end
end
