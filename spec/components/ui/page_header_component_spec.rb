# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::PageHeaderComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:component) { described_class.new(title: "Interviews") }

  # Tracer bullet: renders h1 with title
  it "renders the h1 heading with the given title" do
    expect(rendered.css("h1").text.strip).to eq("Interviews")
  end

  it "does not render breadcrumb nav when no parent is given" do
    expect(rendered.css("[data-testid='breadcrumb']")).to be_empty
  end

  it "does not render notice div when notice is nil" do
    expect(rendered.css("[data-testid='notice']")).to be_empty
  end

  it "does not render alert div when alert is nil" do
    expect(rendered.css("[data-testid='alert']")).to be_empty
  end

  context "with a parent breadcrumb" do
    let(:component) { described_class.new(title: "New Interview", parent: { label: "Interviews", url: "/interviews" }) }

    it "renders the breadcrumb nav" do
      expect(rendered.css("[data-testid='breadcrumb']")).to be_present
    end

    it "renders a link to the parent" do
      link = rendered.css("[data-testid='breadcrumb'] a").first
      expect(link.text.strip).to eq("Interviews")
      expect(link["href"]).to eq("/interviews")
    end

    it "renders the current page label (title) as the last breadcrumb item" do
      current = rendered.css("[data-testid='breadcrumb'] span.text-gray-900").first
      expect(current.text.strip).to eq("New Interview")
    end
  end

  context "with a notice message" do
    let(:component) { described_class.new(title: "Interviews", notice: "Interview created.") }

    it "renders the notice banner" do
      expect(rendered.css("[data-testid='notice']").text.strip).to eq("Interview created.")
    end
  end

  context "with an alert message" do
    let(:component) { described_class.new(title: "Interviews", alert: "Something went wrong.") }

    it "renders the alert banner" do
      expect(rendered.css("[data-testid='alert']").text.strip).to eq("Something went wrong.")
    end
  end

  context "with action slots (config-based)" do
    before do
      component.with_action(type: :link, label: "Edit", url: "/edit")
      component.with_action(type: :delete, label: "Delete", url: "/records/1", confirm: "Sure?")
    end

    it "renders each action slot" do
      expect(rendered.css("a[href='/edit']")).to be_present
      expect(rendered.css("form[action='/records/1']")).to be_present
    end

    it "renders actions in a flex container alongside the h1" do
      header = rendered.css("[data-testid='page-header']").first
      expect(header["class"]).to include("justify-between")
    end
  end

  context "with a :dialog action slot" do
    before do
      component.with_action(
        type: :dialog,
        label: "Delete",
        dialog_title: "Really delete?",
        url: "/items/1",
        method: :delete,
        confirm: "Yes, delete",
        variant: :danger
      )
    end

    it "renders a dialog trigger button in the header" do
      expect(rendered.css("button[data-action='dialog#open']")).to be_present
    end

    it "renders the confirmation dialog" do
      expect(rendered.css("dialog")).to be_present
      expect(rendered.css(".dialog-title").text.strip).to eq("Really delete?")
    end

    it "renders actions in a flex container alongside the h1" do
      header = rendered.css("[data-testid='page-header']").first
      expect(header["class"]).to include("justify-between")
    end
  end

  context "with action slots (raw block, backward-compatible)" do
    before do
      component.with_action { '<a id="edit-link" href="/edit">Edit</a>'.html_safe }
      component.with_action { '<button id="delete-btn">Delete</button>'.html_safe }
    end

    it "renders each action slot" do
      expect(rendered.css("a#edit-link")).to be_present
      expect(rendered.css("button#delete-btn")).to be_present
    end

    it "renders actions in a flex container alongside the h1" do
      header = rendered.css("[data-testid='page-header']").first
      expect(header["class"]).to include("justify-between")
    end
  end

  context "without action slots" do
    it "renders a simple header without justify-between" do
      header = rendered.css("[data-testid='page-header']").first
      expect(header["class"]).not_to include("justify-between")
    end
  end
end
