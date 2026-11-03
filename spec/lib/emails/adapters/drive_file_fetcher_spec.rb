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

  describe "#scan" do
    let(:fields) { "nextPageToken,files(id,name,mimeType,md5Checksum,modifiedTime,webViewLink)" }

    def stub_children(folder_id, files, page_token: nil, next_token: nil)
      query = { q: "'#{folder_id}' in parents and trashed=false", fields: fields, pageSize: 1000, supportsAllDrives: true,
                includeItemsFromAllDrives: true }
      query[:pageToken] = page_token if page_token
      body = { files: files }
      body[:nextPageToken] = next_token if next_token
      stub_request(:get, "https://www.googleapis.com/drive/v3/files").with(query: query)
        .to_return(status: 200, body: body.to_json)
    end

    def file(id, **attrs)
      { id: id, name: "#{id}.pdf", mimeType: "application/pdf", md5Checksum: "md5-#{id}",
        modifiedTime: "2026-01-01T00:00:00.000Z", webViewLink: "https://drive.google.com/file/d/#{id}/view" }.merge(attrs)
    end

    it "lists files recursively across pages, descending into subfolders once" do
      stub_children("root", [ file("a"), { id: "sub", name: "sub", mimeType: described_class::FOLDER_MIME } ],
                    next_token: "p2")
      stub_children("root", [ file("b") ], page_token: "p2")
      stub_children("sub", [ file("c"), { id: "root", name: "loop", mimeType: described_class::FOLDER_MIME } ])

      entries = fetcher.scan([ "root" ])

      expect(entries.map(&:id)).to eq(%w[a b c])
      expect(entries.first).to have_attributes(
        name: "a.pdf", mime_type: "application/pdf", md5: "md5-a",
        modified_time: "2026-01-01T00:00:00.000Z", web_view_link: "https://drive.google.com/file/d/a/view"
      )
    end

    it "returns each file once when folders overlap" do
      stub_children("f1", [ file("a"), { id: "f2", name: "f2", mimeType: described_class::FOLDER_MIME } ])
      stub_children("f2", [ file("a") ])

      expect(fetcher.scan(%w[f1 f2]).map(&:id)).to eq(%w[a])
    end
  end

  describe "Google Docs" do
    it "exports a native document as docx, both via #export and #fetch" do
      export = stub_request(:get, "https://www.googleapis.com/drive/v3/files/g1/export")
        .with(query: { mimeType: described_class::DOCX_MIME, supportsAllDrives: true }, headers: { "Authorization" => "Bearer tok" })
        .to_return(status: 200, body: "docx-bytes")
      stub_request(:get, "https://www.googleapis.com/drive/v3/files/g1?fields=name,mimeType&supportsAllDrives=true")
        .to_return(status: 200, body: { name: "Notes", mimeType: described_class::GOOGLE_DOC_MIME }.to_json)

      expect(fetcher.export("g1")).to eq("docx-bytes")
      file = fetcher.fetch("g1")
      expect([ file.data, file.filename, file.mime_type ]).to eq([ "docx-bytes", "Notes", described_class::DOCX_MIME ])
      expect(export).to have_been_requested.twice
    end
  end

  it "raises NotConfigured without credentials" do
    stub_const("ENV", ENV.to_h.merge("GMAIL_CREDENTIALS_PATH" => "/nonexistent.json"))
    expect { described_class.from_env.fetch("f1") }.to raise_error(described_class::NotConfigured, /not configured/i)
  end
end
