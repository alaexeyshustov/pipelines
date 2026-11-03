require "rails_helper"

RSpec.describe UI::FilterChipComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(label: "bank", href: "/x?subtag=bank", **options)) }

  let(:options) { {} }

  it "renders a link to href with the label" do
    link = rendered.css("a").first
    expect(link.text.strip).to eq("bank")
    expect(link["href"]).to eq("/x?subtag=bank")
  end

  it "is not marked current by default" do
    expect(rendered.css("a").first["aria-current"]).to be_nil
  end

  context "when active" do
    let(:options) { { active: true } }

    it "marks the chip as current" do
      expect(rendered.css("a").first["aria-current"]).to eq("true")
    end
  end
end
