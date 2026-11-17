require "rails_helper"

load Rails.root.join("bin/pipeline").to_s unless defined?(PipelineCLI)

RSpec.describe PipelineCLI::Commands::UploadGist do
  subject(:upload) { described_class.new.call(token: "t0k3n", gist_id: "gist_42", filename: "interviews.csv") }

  it "uploads the interviews CSV and prints the Gist URL" do
    create(:interview, company: "Acme")
    request = stub_request(:patch, "https://api.github.com/gists/gist_42")
              .with { |req| JSON.parse(req.body).dig("files", "interviews.csv", "content").include?("Acme") }
              .to_return(status: 200, body: { html_url: "https://gist.github.com/gist_42" }.to_json)

    expect { upload }.to output("Uploaded: https://gist.github.com/gist_42\n").to_stdout
    expect(request).to have_been_requested
  end

  it "reports a GitHub error and exits" do
    stub_request(:patch, "https://api.github.com/gists/gist_42").to_return(status: 404, body: { message: "Not Found" }.to_json)

    expect { upload }.to output("Upload failed: 404 Not Found\n").to_stdout.and raise_error(SystemExit)
  end
end
