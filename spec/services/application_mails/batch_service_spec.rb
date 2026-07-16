
require "rails_helper"

RSpec.describe ApplicationMails::BatchService do
  describe "#call" do
    context "when action is delete" do
      it "destroys exactly the selected records and leaves others untouched" do
        doomed = create_list(:application_mail, 2)
        kept   = create(:application_mail, email_id: "kept@gmail.com")

        result = described_class.new(ids: doomed.map(&:id), batch_action: "delete").call

        expect(result.ok?).to be true
        expect(result.message).to eq("Deleted 2 record(s).")
        expect(ApplicationMail.all).to contain_exactly(kept)
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
