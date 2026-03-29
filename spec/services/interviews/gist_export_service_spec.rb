# frozen_string_literal: true

require "rails_helper"

RSpec.describe Interviews::GistExportService do
  let!(:interview) do
    create(:interview, company: "Acme", job_title: "Backend",
           status: "pending_reply", applied_at: "2026-01-10")
  end

  describe "#call" do
    context "when GITHUB_TOKEN is not set" do
      before { allow(ENV).to receive(:[]).and_call_original
allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return(nil)  }

      it "returns failure without making an HTTP request" do
        result = described_class.new(ids: [ interview.id ], gist_id: "abc123").call
        expect(result.ok?).to be false
        expect(result.message).to include("GITHUB_TOKEN")
      end
    end

    context "when GITHUB_TOKEN is present", vcr: { cassette_name: "interviews/gist_export/success" } do
      before { allow(ENV).to receive(:[]).and_call_original
allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("fake-token")  }

      it "returns success result" do
        result = described_class.new(ids: [ interview.id ], gist_id: "abc123").call
        expect(result.ok?).to be true
        expect(result.message).to include("abc123")
      end
    end

    context "when gist is not found", vcr: { cassette_name: "interviews/gist_export/not_found" } do
      before { allow(ENV).to receive(:[]).and_call_original
allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("fake-token")  }

      it "returns failure with GitHub error message" do
        result = described_class.new(ids: nil, gist_id: "notfound").call
        expect(result.ok?).to be false
        expect(result.message).to include("Not Found")
      end
    end
  end
end
