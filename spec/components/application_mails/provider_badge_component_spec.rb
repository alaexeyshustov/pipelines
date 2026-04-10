# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationMails::ProviderBadgeComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(status: status)) }

  {
    "gmail" => { label: "Gmail", classes: %w[bg-red-50 text-red-700] },
    "yahoo" => { label: "Yahoo", classes: %w[bg-purple-50 text-purple-700] }
  }.each do |provider, expected|
    context "with provider '#{provider}'" do
      let(:status) { provider }

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
