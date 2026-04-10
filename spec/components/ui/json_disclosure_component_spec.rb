# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::JsonDisclosureComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:label) { "Input" }
  let(:data)  { { "key" => "value" } }
  let(:component) { described_class.new(label: label, data: data) }

  it "renders a details element" do
    expect(rendered.css("details")).to be_present
  end

  it "renders the label in the summary" do
    expect(rendered.css("details summary").first.text.strip).to eq("Input")
  end

  it "renders pretty-printed JSON in a pre element" do
    expect(rendered.css("pre").first.text).to include('"key"')
    expect(rendered.css("pre").first.text).to include('"value"')
  end

  context "when data is nil" do
    let(:data) { nil }

    it "renders nothing" do
      expect(rendered.to_html).to be_empty
    end
  end

  context "when data is an empty hash" do
    let(:data) { {} }

    it "renders nothing" do
      expect(rendered.to_html).to be_empty
    end
  end

  describe "#pretty_json" do
    it "returns pretty-printed JSON" do
      expect(component.pretty_json).to eq(JSON.pretty_generate("key" => "value"))
    end
  end

  describe "#render?" do
    it "returns true when data is present" do
      expect(component.render?).to be(true)
    end

    context "when data is nil" do
      let(:data) { nil }

      it "returns false" do
        expect(component.render?).to be(false)
      end
    end
  end
end
