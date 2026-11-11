require "rails_helper"

RSpec.describe "Tags" do
  let!(:tag) { create(:tag, name: "finance") }

  describe "GET /tags" do
    it "lists tags with their subtags" do
      create(:subtag, tag:, name: "bank")
      get tags_path
      expect(response).to be_successful
      expect(response.body).to include("finance", "bank")
    end
  end

  describe "POST /tags/:tag_id/subtags" do
    it "adds a subtag" do
      expect { post tag_subtags_path(tag), params: { subtag: { name: "receipt" } } }
        .to change { tag.subtags.count }.by(1)
      expect(response).to redirect_to(tags_path)
    end

    it "re-renders with errors for a duplicate" do
      create(:subtag, tag:, name: "bank")
      expect { post tag_subtags_path(tag), params: { subtag: { name: "bank" } } }
        .not_to change(Subtag, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already been taken")
    end
  end
end
