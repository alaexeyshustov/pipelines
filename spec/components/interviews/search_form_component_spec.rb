# frozen_string_literal: true

require "rails_helper"

RSpec.describe Interviews::SearchFormComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(url: "/interviews", query: nil, clear_url: "/interviews")) }

  it "inherits from UI::SearchFormComponent" do
    expect(described_class.superclass).to eq(UI::SearchFormComponent)
  end

  it "uses the interviews-specific placeholder" do
    expect(rendered.css("input[name='q']").first["placeholder"]).to eq("Search by company or job title…")
  end
end
