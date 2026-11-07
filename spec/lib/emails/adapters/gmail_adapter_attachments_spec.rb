require "rails_helper"

RSpec.describe Emails::Adapters::GmailAdapter, "#attachments" do
  include GmailHelpers

  subject(:adapter) do
    described_class.from_env(credentials_path: GmailHelpers::CREDENTIALS_PATH, token_path: GmailHelpers.token_path)
  end

  after  { teardown_gmail }

  def part(filename:, mime:, attachment_id: nil, size: 10, parts: nil, disposition: nil)
    headers = disposition && [ { name: "Content-Disposition", value: disposition } ]
    { filename: filename, mimeType: mime, body: { attachmentId: attachment_id, size: size }.compact, parts: parts,
      headers: headers }.compact
  end

  let(:payload) do
    part(filename: "", mime: "multipart/mixed", parts: [
      part(filename: "", mime: "text/plain"),
      part(filename: "cv.pdf", mime: "application/pdf", attachment_id: "att1", size: 1234),
      part(filename: "", mime: "multipart/related", parts: [ part(filename: "logo.png", mime: "image/png", attachment_id: "att2", size: 5) ])
    ])
  end

  before do
    setup_gmail
    stub_request(:get, %r{#{GmailHelpers::GMAIL_BASE_URL}/messages/msg1\?format=full}o)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "msg1", payload: payload }.to_json)
  end

  it "lists nested attachment parts as metadata and skips inline bodies" do
    expect(adapter.attachments("msg1")).to eq([
      { id: "att1", filename: "cv.pdf", mime_type: "application/pdf", size: 1234 },
      { id: "att2", filename: "logo.png", mime_type: "image/png", size: 5 }
    ])
  end

  context "with inline parts such as signature logos" do
    let(:payload) do
      part(filename: "", mime: "multipart/mixed", parts: [
        part(filename: "cv.pdf", mime: "application/pdf", attachment_id: "att1", disposition: "attachment; filename=\"cv.pdf\""),
        part(filename: "image001.png", mime: "image/png", attachment_id: "att2", disposition: "inline; filename=\"image001.png\""),
        part(filename: "image002.png", mime: "image/png", attachment_id: "att3", disposition: "Inline")
      ])
    end

    it "skips parts whose Content-Disposition is inline" do
      expect(adapter.attachments("msg1").pluck(:id)).to eq(%w[att1])
    end
  end
end
