# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::NavbarComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:component) { described_class.new(current_path: "/") }

  it "renders the brand link" do
    brand = rendered.css("[data-testid='navbar-brand']").first
    expect(brand.text.strip).to eq("Application Pipeline")
    expect(brand["href"]).to eq("/")
  end

  it "renders all nav items" do
    items = rendered.css("[data-testid='navbar-item']")
    labels = items.map { |n| n.text.strip }
    expect(labels).to eq(%w[Chats Pipelines Actions Emails Interviews])
  end

  it "renders a nav element" do
    expect(rendered.css("[data-testid='navbar']")).to be_present
  end

  context "when on a nav item path" do
    let(:component) { described_class.new(current_path: "/chats") }

    it "highlights the active item with font-medium" do
      chats_link = rendered.css("[data-testid='navbar-item']").first
      expect(chats_link["class"]).to include("font-medium")
    end

    it "does not highlight inactive items" do
      non_active = rendered.css("[data-testid='navbar-item']").to_a.drop(1)
      non_active.each do |link|
        expect(link["class"]).not_to include("font-medium")
      end
    end
  end

  context "when not on any nav item path" do
    it "renders no nav item as active" do
      items = rendered.css("[data-testid='navbar-item']")
      items.each do |link|
        expect(link["class"]).not_to include("font-medium")
      end
    end
  end
end
