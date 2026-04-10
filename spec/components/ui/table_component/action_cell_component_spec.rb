# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TableComponent::ActionCellComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:component) { described_class.new }

  it "renders a td with right-aligned flex layout classes" do
    td = rendered.css("td").first
    expect(td).to be_present
    expect(td["class"]).to include("px-4", "py-3", "text-right", "flex", "justify-end", "gap-3")
  end

  it "applies compact padding when style: :compact" do
    component = described_class.new(style: :compact)
    rendered = render_inline(component)

    expect(rendered.css("td").first["class"]).to include("px-6", "py-4")
  end

  context "with a default link action" do
    before { component.with_action(label: "View", url: "/records/1") }

    it "renders a link with correct text and href" do
      link = rendered.css("td a").first
      expect(link).to be_present
      expect(link.text.strip).to eq("View")
      expect(link["href"]).to eq("/records/1")
    end

    it "applies default variant classes to the link" do
      link = rendered.css("td a").first
      expect(link["class"]).to include("text-gray-500", "font-medium")
    end
  end

  context "with a primary link action" do
    before { component.with_action(label: "Edit", url: "/records/1/edit", variant: :primary) }

    it "renders a link with primary variant classes" do
      link = rendered.css("td a").first
      expect(link["class"]).to include("text-indigo-600")
    end
  end

  context "with a danger button action (delete)" do
    before do
      component.with_action(
        label: "Delete",
        url: "/records/1",
        method: :delete,
        variant: :danger,
        confirm: "Delete this record?"
      )
    end

    it "renders a form-based button (not a link)" do
      expect(rendered.css("td form")).to be_present
      expect(rendered.css("td a")).to be_empty
    end

    it "applies danger variant classes to the button" do
      btn = rendered.css("td form button").first
      expect(btn["class"]).to include("text-red-500")
    end

    it "sets turbo_confirm on the form" do
      form = rendered.css("td form").first
      expect(form["data-turbo-confirm"]).to eq("Delete this record?")
    end
  end

  context "with raw content block" do
    it "renders arbitrary content inside the td alongside actions" do
      component.with_action(label: "Edit", url: "/records/1/edit", variant: :primary)
      rendered = render_inline(component) { "<span class='custom'>Custom</span>".html_safe }

      expect(rendered.css("td a").first.text.strip).to eq("Edit")
      expect(rendered.css("td span.custom").first.text).to eq("Custom")
    end
  end

  context "with multiple actions" do
    before do
      component.with_action(label: "View", url: "/r/1")
      component.with_action(label: "Edit", url: "/r/1/edit", variant: :primary)
      component.with_action(label: "Delete", url: "/r/1", method: :delete, variant: :danger, confirm: "Sure?")
    end

    it "renders all three actions" do
      links = rendered.css("td a")
      expect(links.size).to eq(2)
      expect(rendered.css("td form")).to be_present
    end
  end
end
