require "rails_helper"

RSpec.describe "Searches" do
  describe "GET /search" do
    it "returns emails and documents, grouped, with highlighted snippets" do
      create(:email, subject: "Offer from Acme", body: "salary details")
      create(:document, title: "Lease", text: "salary appendix")
      get search_path, params: { q: "salary" }
      expect(response.body).to include("Emails", "Documents", "Offer from Acme", "Lease", "<mark>salary</mark>")
      expect(response.body.index("Emails")).to be < response.body.index("Documents")
    end

    it "links documents" do
      document = create(:document, text: "salary")
      get search_path, params: { q: "salary" }
      expect(response.body).to include(document_path(document))
    end

    it "escapes raw content in snippets" do
      create(:email, body: "salary <script>alert(1)</script>")
      get search_path, params: { q: "salary" }
      expect(response.body).not_to include("<script>alert(1)")
      expect(response.body).to include("&lt;script&gt;")
    end

    it "shows an empty state for a blank query" do
      get search_path, params: { q: "  " }
      expect(response).to be_successful
      expect(response.body).to include("Enter a search term")
    end

    it "shows no results message when nothing matches" do
      get search_path, params: { q: "zzzz" }
      expect(response.body).to include("No results")
    end

    it "does not raise on hostile input" do
      get search_path, params: { q: %q(" OR * NEAR( ) -- ' AND) }
      expect(response).to be_successful
    end
  end
end
