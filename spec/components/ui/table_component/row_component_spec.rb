# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TableComponent::RowComponent, type: :component do
  it "renders a tr element with hover classes" do
    rendered = render_inline(described_class.new) { "content" }

    tr = rendered.css("tr").first
    expect(tr).to be_present
    expect(tr["class"]).to include("hover:bg-gray-50", "transition-colors")
  end

  it "yields content inside the tr" do
    rendered = render_inline(described_class.new) { "<td>Hello</td>".html_safe }

    expect(rendered.css("tr td").text).to eq("Hello")
  end
end
