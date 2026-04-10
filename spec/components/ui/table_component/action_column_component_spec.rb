require "rails_helper"

RSpec.describe UI::TableComponent::ActionColumnComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:component) { described_class.new }

  it "renders an empty th header" do
    expect(rendered.css("th").first).to be_present
    expect(rendered.css("th").first.text.strip).to eq("")
  end

  it "applies default padding to the header" do
    expect(rendered.css("th").first["class"]).to include("px-4", "py-3")
  end

  it "applies compact padding when style: :compact" do
    rendered = render_inline(described_class.new(style: :compact))
    expect(rendered.css("th").first["class"]).to include("px-6", "py-3")
  end

  describe "#render_cell" do
    let(:record) { Data.define(:id).new(id: 1) }

    context "without actions proc" do
      it "returns an empty string" do
        expect(component.render_cell(record)).to eq("")
      end
    end

    context "with actions proc" do
      let(:component) do
        described_class.new(
          actions: ->(_r) {
            [
              { label: "Edit", url: "/edit", variant: :primary },
              { label: "Delete", url: "/delete", method: :delete, variant: :danger, confirm: "Sure?" }
            ]
          }
        )
      end

      before { render_inline(component) }

      it "renders an action cell for the record" do
        result = component.render_cell(record)
        expect(result).to include("Edit")
        expect(result).to include("Delete")
      end
    end
  end
end
