require "rails_helper"

RSpec.describe "Documents" do
  describe "GET /documents" do
    it "lists documents and searches by text" do
      create(:document, title: "Lease", text: "monthly rent")
      create(:document, title: "Offer", text: "salary")
      get documents_path, params: { q: "rent" }
      expect(response.body).to include("Lease")
      expect(response.body).not_to include("Offer")
    end

    it "renders pagination when there is more than one page" do
      create_list(:document, 25)
      get documents_path
      expect(response.body).to include('aria-label="Pagination"', "page=2")
    end

    it "highlights snippet hits and escapes the rest" do
      create(:document, title: "Lease", text: "monthly rent <script>alert(1)</script>")
      get documents_path, params: { q: "rent" }
      expect(response.body).to include("<mark>rent</mark>")
      expect(response.body).not_to include("<script>alert(1)")
    end

    it "lists everything without a query" do
      create(:document, title: "Lease")
      get documents_path
      expect(response.body).to include("Lease")
    end
  end

  describe "GET /documents/:id" do
    it "shows the extracted text and a download link" do
      document = create(:document, text: "Hello extracted")
      get document_path(document)
      expect(response.body).to include("Hello extracted", download_document_path(document))
    end
  end

  describe "GET /documents/:id source link" do
    it "links an http source with noopener noreferrer" do
      document = create(:document, source_url: "https://mail.google.com/mail/u/0/#inbox/abc")
      get document_path(document)
      expect(response.body).to include('href="https://mail.google.com/mail/u/0/#inbox/abc"', 'rel="noopener noreferrer"')
    end

    it "renders the page without a link when the source URL is not a valid URI" do
      document = create(:document, source_url: "https://example.com/a b")
      get document_path(document)
      expect(response).to be_successful
      expect(response.body).not_to include("Open source")
    end
  end

  describe "GET /documents/:id/download" do
    let(:document) { create(:document, title: "Offer letter") }

    it "streams the original file" do
      result = Document::Download::File.new(data: "%PDF-", filename: "Offer letter.pdf", mime_type: "application/pdf")
      allow(Document::Download).to receive(:call).with(document).and_return(result)

      get download_document_path(document)

      expect(response.body).to eq("%PDF-")
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment", "Offer letter.pdf")
    end

    it "redirects back with a generic alert that leaks no detail when the original cannot be fetched" do
      allow(Document::Download).to receive(:call)
        .and_raise(Emails::Adapters::DriveFileFetcher::NotConfigured, "expected /srv/app/credentials.json")
      get download_document_path(document)
      expect(response).to redirect_to(document_path(document))
      expect(flash[:alert]).to eq("Could not fetch the original file.")
    end

    it "logs the failure detail" do
      allow(Document::Download).to receive(:call).and_raise(StandardError, "secret detail")
      allow(Rails.logger).to receive(:error)
      get download_document_path(document)
      expect(Rails.logger).to have_received(:error).with(/secret detail/)
    end

    it "answers 404 for an unknown document" do
      get download_document_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
