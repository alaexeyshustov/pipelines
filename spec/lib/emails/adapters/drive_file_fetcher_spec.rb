require "rails_helper"

RSpec.describe Emails::Adapters::DriveFileFetcher do
  subject(:fetcher) { described_class.new(access_token: -> { "tok" }) }

  it "fetches file name, mime type and bytes with a bearer token" do
    stub_request(:get, "https://www.googleapis.com/drive/v3/files/f1?fields=name,mimeType&supportsAllDrives=true")
      .with(headers: { "Authorization" => "Bearer tok" })
      .to_return(status: 200, body: { name: "cv.pdf", mimeType: "application/pdf" }.to_json)
    stub_request(:get, "https://www.googleapis.com/drive/v3/files/f1?alt=media&supportsAllDrives=true")
      .with(headers: { "Authorization" => "Bearer tok" })
      .to_return(status: 200, body: "%PDF-")

    file = fetcher.fetch("f1")
    expect([ file.data, file.filename, file.mime_type ]).to eq([ "%PDF-", "cv.pdf", "application/pdf" ])
  end

  it "raises a clear error on a failed request" do
    stub_request(:get, %r{drive/v3/files/gone}).to_return(status: 404, body: "{}")
    expect { fetcher.fetch("gone") }.to raise_error(described_class::Error, /404/)
  end

  it "raises NotConfigured without credentials" do
    stub_const("ENV", ENV.to_h.merge("GMAIL_CREDENTIALS_PATH" => "/nonexistent.json"))
    expect { described_class.from_env.fetch("f1") }.to raise_error(described_class::NotConfigured, /not configured/i)
  end
end
