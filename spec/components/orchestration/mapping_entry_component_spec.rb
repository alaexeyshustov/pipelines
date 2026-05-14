# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::MappingEntryComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:row) do
    Orchestration::InputMappingComponent::MappingRow.new(
      mapping_key:  "email_body",
      current_from: "_initial",
      current_path: "body",
      path_opts:    [["body", "body"], ["subject", "subject"]]
    )
  end
  let(:from_options) { [["_initial", "_initial"], ["classification", "classification"]] }
  let(:component) { described_class.new(row: row, from_options: from_options) }

  it "renders the mapping key label" do
    expect(rendered.css("span").first.text.strip).to eq("email_body")
  end

  it "renders the from select with data-testid" do
    expect(rendered.css("[data-testid='from-select']")).to be_present
  end

  it "renders the path select when path_opts are present" do
    expect(rendered.css("[data-testid='path-select']")).to be_present
    expect(rendered.css("[data-testid='path-text']")).to be_empty
  end

  context "when path_opts is nil" do
    let(:row) do
      Orchestration::InputMappingComponent::MappingRow.new(
        mapping_key:  "custom_key",
        current_from: "_initial",
        current_path: "some.path",
        path_opts:    nil
      )
    end

    it "renders the path text field" do
      expect(rendered.css("[data-testid='path-text']")).to be_present
      expect(rendered.css("[data-testid='path-select']")).to be_empty
    end
  end
end
