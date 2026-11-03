require "rails_helper"

RSpec.describe "Document duplicates" do
  let(:document) { create(:document, title: "Lease.pdf") }
  let(:other) { create(:document, title: "Lease scan.pdf") }
  let!(:duplicate) { DocumentDuplicate.flag!(document, other, similarity: 0.973) }

  it "lists candidates with a link and similarity on both documents" do
    get document_path(document)
    expect(response.body).to include("Possible duplicates", "Lease scan.pdf", document_path(other), "97.3%")

    get document_path(other)
    expect(response.body).to include("Lease.pdf", document_path(document), "97.3%")
  end

  it "shows no section without candidates" do
    get document_path(create(:document))

    expect(response.body).not_to include("Possible duplicates")
  end

  it "does not run a query per candidate" do
    3.times { DocumentDuplicate.flag!(document, create(:document), similarity: 0.96) }
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('FROM "documents"') }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get document_path(document) }

    expect(queries.size).to be <= 3
  end

  it "confirms a candidate and keeps showing it as confirmed" do
    patch confirm_document_duplicate_path(document, duplicate)

    expect(response).to redirect_to(document_path(document))
    expect(duplicate.reload.status).to eq("confirmed")
    get document_path(other)
    expect(response.body).to include("Confirmed duplicate")
  end

  it "dismisses a candidate and hides it from both documents" do
    patch dismiss_document_duplicate_path(document, duplicate)

    expect(duplicate.reload.status).to eq("dismissed")
    get document_path(document)
    expect(response.body).not_to include("Possible duplicates")
  end

  it "is not found through an unrelated document" do
    patch confirm_document_duplicate_path(create(:document), duplicate)

    expect(response).to have_http_status(:not_found)
  end
end
