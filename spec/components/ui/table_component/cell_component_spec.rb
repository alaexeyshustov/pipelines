# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TableComponent::CellComponent, type: :component do
  it "renders a td with default padding and yields content" do
    rendered = render_inline(described_class.new) { "Hello" }

    td = rendered.css("td").first
    expect(td).to be_present
    expect(td["class"]).to include("px-4", "py-3")
    expect(td.text).to eq("Hello")
  end

  it "applies compact padding when style: :compact" do
    rendered = render_inline(described_class.new(style: :compact)) { "x" }

    td = rendered.css("td").first
    expect(td["class"]).to include("px-6", "py-4")
  end

  it "applies muted variant text class" do
    rendered = render_inline(described_class.new(variant: :muted)) { "x" }

    expect(rendered.css("td").first["class"]).to include("text-gray-500")
  end

  it "applies subtle variant text class" do
    rendered = render_inline(described_class.new(variant: :subtle)) { "x" }

    expect(rendered.css("td").first["class"]).to include("text-gray-600")
  end

  it "applies strong variant classes" do
    rendered = render_inline(described_class.new(variant: :strong)) { "x" }

    td = rendered.css("td").first
    expect(td["class"]).to include("font-medium", "text-gray-900")
  end

  it "applies mono variant classes" do
    rendered = render_inline(described_class.new(variant: :mono)) { "x" }

    td = rendered.css("td").first
    expect(td["class"]).to include("font-mono", "text-xs")
  end

  it "overrides with custom classes when provided" do
    rendered = render_inline(described_class.new(classes: "custom-class")) { "x" }

    expect(rendered.css("td").first["class"]).to eq("custom-class")
  end
end
