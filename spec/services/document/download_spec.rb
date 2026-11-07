require "rails_helper"

RSpec.describe Document::Download do
  include GmailHelpers

  before { setup_gmail }
  after  { teardown_gmail }

  it "fetches a Gmail attachment via source_ref" do
    stub_request(:get, "#{GmailHelpers::GMAIL_BASE_URL}/messages/msg_1/attachments/att_1")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { size: 5, data: Base64.urlsafe_encode64("%PDF-") }.to_json)
    document = create(:document, title: "Offer letter", mime_type: "application/pdf")

    file = described_class.call(document)

    expect([ file.data, file.filename, file.mime_type ]).to eq([ "%PDF-", "Offer letter.pdf", "application/pdf" ])
  end

  it "keeps a title that already has an extension" do
    stub_request(:get, %r{attachments/att_1}).to_return(
      status: 200, headers: { "Content-Type" => "application/json" }, body: { data: Base64.urlsafe_encode64("x") }.to_json
    )
    expect(described_class.call(create(:document, title: "offer.pdf")).filename).to eq("offer.pdf")
  end

  it "fetches a Drive file via source_ref" do
    stub_request(:get, %r{drive/v3/files/f1\?fields}).to_return(
      status: 200, body: { name: "cv.docx", mimeType: "application/vnd.x" }.to_json
    )
    stub_request(:get, %r{drive/v3/files/f1\?alt=media}).to_return(status: 200, body: "bytes")
    allow(Emails::Adapters::DriveFileFetcher).to receive(:from_env)
      .and_return(Emails::Adapters::DriveFileFetcher.new(access_token: -> { "tok" }))
    document = create(:document, source: "drive", source_ref: { "provider" => "drive", "drive_file_id" => "f1" })

    expect(described_class.call(document).data).to eq("bytes")
  end

  it "raises for an unsupported source_ref" do
    document = create(:document, source_ref: { "provider" => "yahoo" })
    expect { described_class.call(document) }.to raise_error(described_class::Unsupported)
  end
end
