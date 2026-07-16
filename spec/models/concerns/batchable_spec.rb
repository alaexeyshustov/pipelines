
require "rails_helper"

RSpec.describe Batchable do
  describe ".destroy_by_ids" do
    let!(:kept)     { create(:application_mail, email_id: "kept@gmail.com") }
    let!(:doomed)   { create(:application_mail, email_id: "doomed@gmail.com") }
    let!(:doomed_b) { create(:application_mail, email_id: "doomed_b@gmail.com") }

    it "destroys exactly the records with the given ids" do
      ApplicationMail.destroy_by_ids([ doomed.id, doomed_b.id ])

      expect(ApplicationMail.exists?(doomed.id)).to be false
      expect(ApplicationMail.exists?(doomed_b.id)).to be false
    end

    it "leaves other records untouched" do
      ApplicationMail.destroy_by_ids([ doomed.id, doomed_b.id ])

      expect(ApplicationMail.all).to contain_exactly(kept)
    end

    it "destroys nothing when given no ids" do
      expect { ApplicationMail.destroy_by_ids([]) }.not_to change(ApplicationMail, :count)
    end
  end
end
