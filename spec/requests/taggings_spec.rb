require "rails_helper"

RSpec.describe "Taggings" do
  let(:tag) { create(:tag, name: "finance") }
  let(:subtag) { create(:subtag, tag:, name: "bank") }

  describe "GET /emails/:id" do
    it "shows the email and its tags" do
      email = create(:email, subject: "Invoice due", body: "Pay soon")
      create(:tagging, taggable: email, tag:, subtag:, source: "llm", confidence: 0.9)
      get email_path(email)
      expect(response.body).to include("Invoice due", "Pay soon", "finance", "bank")
    end
  end

  [ [ :email, :emails ], [ :document, :documents ] ].each do |factory, _|
    describe "manual tagging on a #{factory}" do
      let(:taggable) { create(factory) }
      let(:collection_path) { send("#{factory}_taggings_path", taggable) }

      it "adds a manual tag with a subtag" do
        expect { post collection_path, params: { tagging: { tag_id: tag.id, subtag_id: subtag.id } } }
          .to change { taggable.taggings.manual.count }.by(1)
        expect(response).to redirect_to(send("#{factory}_path", taggable))
        expect(taggable.taggings.last).to have_attributes(tag:, subtag:, source: "manual")
      end

      it "re-renders the page with errors for an invalid subtag" do
        other = create(:subtag)
        post collection_path, params: { tagging: { tag_id: tag.id, subtag_id: other.id } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("must belong to the selected tag")
      end

      it "removes a tagging" do
        tagging = create(:tagging, taggable:, tag:, source: "llm")
        expect { delete "#{collection_path}/#{tagging.id}" }.to change { taggable.taggings.count }.by(-1)
        expect(response).to redirect_to(send("#{factory}_path", taggable))
      end

      it "does not remove another item's tagging" do
        foreign = create(:tagging, taggable: create(factory), tag:)
        delete "#{collection_path}/#{foreign.id}"
        expect(response).to have_http_status(:not_found)
        expect(Tagging.exists?(foreign.id)).to be(true)
      end
    end
  end
end
