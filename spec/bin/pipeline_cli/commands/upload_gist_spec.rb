require "rails_helper"

load Rails.root.join("bin/pipeline").to_s unless defined?(PipelineCLI)

RSpec.describe PipelineCLI::Commands::UploadGist do
  subject(:upload) { described_class.new.call(token: "t0k3n", gist_id: "abc123", filename: "interviews.csv") }

  def stub_gist_get(public: false)
    stub_request(:get, "https://api.github.com/gists/abc123")
      .to_return(status: 200, body: { public: public }.to_json)
  end

  def uploaded_csv(request_body)
    CSV.parse(JSON.parse(request_body).dig("files", "interviews.csv", "content"), headers: true)
  end

  it "uploads the interviews CSV and prints the Gist URL" do
    create(:interview, company: "Acme")
    stub_gist_get
    request = stub_request(:patch, "https://api.github.com/gists/abc123")
              .with { |req| JSON.parse(req.body).dig("files", "interviews.csv", "content").include?("Acme") }
              .to_return(status: 200, body: { html_url: "https://gist.github.com/abc123" }.to_json)

    expect { upload }.to output("Uploaded: https://gist.github.com/abc123\n").to_stdout
    expect(request).to have_been_requested
  end

  it "reports a GitHub error and exits" do
    stub_request(:get, "https://api.github.com/gists/abc123").to_return(status: 404, body: { message: "Not Found" }.to_json)

    expect { upload }.to output("Upload failed: 404 Not Found\n").to_stdout.and raise_error(SystemExit)
  end

  it "uploads a CSV without an id column and with formula cells prefixed" do
    create(:interview, company: "=cmd")
    stub_gist_get
    body = nil
    stub_request(:patch, "https://api.github.com/gists/abc123")
      .with { |req| body = req.body }
      .to_return(status: 200, body: { html_url: "https://gist.github.com/abc123" }.to_json)

    expect { upload }.to output(/Uploaded/).to_stdout
    csv = uploaded_csv(body)
    expect(csv.headers).not_to include("id")
    expect(csv.first["company"]).to eq("'=cmd")
  end

  it "creates a private gist when no id is given and GIST_ID is empty" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GIST_ID").and_return("")
    create(:interview, company: "Acme")
    request = stub_request(:post, "https://api.github.com/gists")
              .with(body: hash_including("public" => false))
              .to_return(status: 201, body: { html_url: "https://gist.github.com/new" }.to_json)

    expect { described_class.new.call(token: "t0k3n", filename: "interviews.csv") }
      .to output("Uploaded: https://gist.github.com/new\n").to_stdout
    expect(request).to have_been_requested
  end

  it "falls back to GIST_ID when --gist_id is blank" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GIST_ID").and_return("abc123")
    stub_gist_get
    request = stub_request(:patch, "https://api.github.com/gists/abc123")
              .to_return(status: 200, body: { html_url: "https://gist.github.com/abc123" }.to_json)

    expect { described_class.new.call(token: "t0k3n", gist_id: "", filename: "interviews.csv") }
      .to output("Uploaded: https://gist.github.com/abc123\n").to_stdout
    expect(request).to have_been_requested
  end

  it "rejects an invalid --gist_id without any HTTP request" do
    expect { described_class.new.call(token: "t0k3n", gist_id: "../x", filename: "interviews.csv") }
      .to output(/\AUpload failed: .+/).to_stdout.and raise_error(SystemExit)
    expect(WebMock).not_to have_requested(:any, /github\.com/)
  end
end
