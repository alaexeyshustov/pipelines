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

  context "with variant :success" do
    let(:variant) { :success }

    it "applies green styling" do
      expect(rendered.css("span").first["class"]).to include("bg-green-50", "text-green-700")
    end
  end

  context "with variant :warning" do
    let(:variant) { :warning }

    it "applies yellow styling" do
      expect(rendered.css("span").first["class"]).to include("bg-yellow-50", "text-yellow-700")
    end
  end

  context "with variant :danger" do
    let(:variant) { :danger }

    it "applies red styling" do
      expect(rendered.css("span").first["class"]).to include("bg-red-50", "text-red-700")
    end
  end

  context "with variant :info" do
    let(:variant) { :info }

    it "applies blue styling" do
      expect(rendered.css("span").first["class"]).to include("bg-blue-50", "text-blue-700")
    end
  end

  context "with variant :secondary" do
    let(:variant) { :secondary }

    it "applies purple styling" do
      expect(rendered.css("span").first["class"]).to include("bg-purple-50", "text-purple-700")
    end
  end

  context "with variant :neutral" do
    let(:variant) { :neutral }

    it "applies gray styling" do
      expect(rendered.css("span").first["class"]).to include("bg-gray-50", "text-gray-700")
    end
  end

  context "with unknown variant" do
    let(:variant) { :unknown }

    it "falls back to neutral classes" do
      expect(rendered.css("span").first["class"]).to include("bg-gray-50", "text-gray-700")
    end
  end
end
