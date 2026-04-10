# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::RunStatusBadgeComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(status: status)) }

  {
    "completed" => %w[bg-green-50 text-green-700],
    "running"   => %w[bg-blue-50 text-blue-700],
    "failed"    => %w[bg-red-50 text-red-700],
    "pending"   => %w[bg-gray-50 text-gray-700]
  }.each do |status_val, classes|
    context "with status '#{status_val}'" do
      let(:status) { status_val }

      it "applies correct color classes" do
        classes.each do |klass|
          expect(rendered.css("span").first["class"]).to include(klass)
        end
      end

      it "renders the status as label" do
        expect(rendered.css("span").text.strip).to eq(status_val.capitalize)
      end
    end
  end
end
