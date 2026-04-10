# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::StatusBadgeComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(label: label, variant: variant)) }

  let(:label) { "Active" }
  let(:variant) { :success }

  it "renders a span with the label" do
    expect(rendered.css("span").text.strip).to eq("Active")
  end

  it "includes the base badge classes" do
    span = rendered.css("span").first
    expect(span["class"]).to include("inline-flex", "items-center", "rounded", "text-xs", "font-medium")
  end

  described_class::VARIANT_CLASSES.each do |v, classes|
    context "with variant :#{v}" do
      let(:variant) { v }

      it "applies #{classes}" do
        classes.split.each do |klass|
          expect(rendered.css("span").first["class"]).to include(klass)
        end
      end
    end
  end

  context "with unknown variant" do
    let(:variant) { :unknown }

    it "falls back to neutral classes" do
      expect(rendered.css("span").first["class"]).to include("bg-gray-50", "text-gray-700")
    end
  end
end
