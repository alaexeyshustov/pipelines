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
