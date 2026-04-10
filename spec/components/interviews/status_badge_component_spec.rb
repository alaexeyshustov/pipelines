# frozen_string_literal: true

require "rails_helper"

RSpec.describe Interviews::StatusBadgeComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(status: status)) }

  {
    "pending_reply"     => { label: "Pending reply",     classes: %w[bg-yellow-50 text-yellow-700] },
    "having_interviews" => { label: "Having interviews", classes: %w[bg-blue-50 text-blue-700] },
    "rejected"          => { label: "Rejected",          classes: %w[bg-red-50 text-red-700] },
    "offer_received"    => { label: "Offer received",    classes: %w[bg-green-50 text-green-700] },
    nil                 => { label: "—",                 classes: %w[bg-gray-50 text-gray-700] }
  }.each do |status_val, expected|
    context "with status #{status_val.inspect}" do
      let(:status) { status_val }

      it "renders label '#{expected[:label]}'" do
        expect(rendered.css("span").text.strip).to eq(expected[:label])
      end

      it "applies correct color classes" do
        expected[:classes].each do |klass|
          expect(rendered.css("span").first["class"]).to include(klass)
        end
      end
    end
  end
end
