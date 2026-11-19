require "rails_helper"

RSpec.describe Interviews::GistExportService do
  let!(:interview) do
    create(:interview, company: "Acme", job_title: "Backend",
           status: "pending_reply", applied_at: "2026-01-10")
  end

  def stub_env(token: "fake-token", gist_id: nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return(token)
    allow(ENV).to receive(:[]).with("GIST_ID").and_return(gist_id)
  end

  describe ".call" do
    context "when GITHUB_TOKEN is not set" do
      before { stub_env(token: nil, gist_id: "abc123") }

      it "returns failure without making an HTTP request" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to include("GITHUB_TOKEN")
        expect(WebMock).not_to have_requested(:any, /github\.com/)
      end
    end

    context "when GITHUB_TOKEN is an empty string" do
      before { stub_env(token: "", gist_id: "abc123") }

      it "returns the token failure" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.message).to eq("GITHUB_TOKEN is not configured.")
      end
    end

    context "when both GITHUB_TOKEN and GIST_ID are missing" do
      before { stub_env(token: nil, gist_id: nil) }

      it "reports the token first and makes no request" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to eq("GITHUB_TOKEN is not configured.")
        expect(WebMock).not_to have_requested(:any, /github\.com/)
      end
    end

    context "when GIST_ID is nil" do
      before { stub_env(gist_id: nil) }

      it "returns the GIST_ID failure" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to eq("GIST_ID is not configured.")
      end
    end

    context "when GIST_ID is blank" do
      before { stub_env(gist_id: "") }

      it "returns failure without making an HTTP request" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to include("GIST_ID is not configured.")
        expect(WebMock).not_to have_requested(:any, /github\.com/)
      end
    end

    context "when GIST_ID is not a valid gist id" do
      before { stub_env(gist_id: "../user") }

      it "returns failure without making an HTTP request" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to eq("Invalid gist ID")
        expect(WebMock).not_to have_requested(:any, /github\.com/)
      end
    end

    context "when the gist is configured", vcr: { cassette_name: "interviews/gist_export/success" } do
      before { stub_env(gist_id: "abc123") }

      it "returns success result" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be true
        expect(result.message).to eq("Interviews exported to gist abc123.")
      end
    end

    context "when gist is not found", vcr: { cassette_name: "interviews/gist_export/not_found" } do
      before { stub_env(gist_id: "deadbeef") }

      it "returns failure with GitHub error message" do
        result = described_class.call(ids: nil)
        expect(result.ok?).to be false
        expect(result.message).to include("Not Found")
      end
    end

    context "when the gist is public" do
      before do
        stub_env(gist_id: "abc123")
        stub_request(:get, "https://api.github.com/gists/abc123")
          .to_return(status: 200, body: { public: true }.to_json)
      end

      it "returns failure and never sends a PATCH" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to include("public")
        expect(WebMock).not_to have_requested(:patch, /github\.com/)
      end
    end

    context "when GitHub returns a non-JSON error page" do
      before do
        stub_env(gist_id: "abc123")
        stub_request(:get, "https://api.github.com/gists/abc123")
          .to_return(status: 502, body: "<html>Bad Gateway</html>")
      end

      it "returns failure with the status code" do
        result = described_class.call(ids: [ interview.id ])
        expect(result.ok?).to be false
        expect(result.message).to eq("GitHub API error (502)")
      end
    end
  end
end
