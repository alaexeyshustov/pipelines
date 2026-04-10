require "rails_helper"

RSpec.describe InterviewsHelper do
  describe "#interview_status_badge_class" do
    {
      "pending_reply"     => "bg-yellow-50 text-yellow-700",
      "having_interviews" => "bg-blue-50 text-blue-700",
      "rejected"          => "bg-red-50 text-red-700",
      "offer_received"    => "bg-green-50 text-green-700"
    }.each do |status, expected_class|
      it "returns #{expected_class} for #{status}" do
        expect(helper.interview_status_badge_class(status)).to eq(expected_class)
      end
    end

    it "returns the default class for an unknown status" do
      expect(helper.interview_status_badge_class("unknown")).to eq("bg-gray-50 text-gray-700")
    end

    it "returns the default class for nil" do
      expect(helper.interview_status_badge_class(nil)).to eq("bg-gray-50 text-gray-700")
    end
  end
end
