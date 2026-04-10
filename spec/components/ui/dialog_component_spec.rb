# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::DialogComponent, type: :component do
  subject(:rendered) do
    render_inline(component) do |c|
      c.with_confirm_action { '<button id="confirm-btn" type="submit">Yes, delete</button>'.html_safe }
    end
  end

  let(:component) do
    described_class.new(
      label: "Delete",
      dialog_title: "Delete this item?"
    )
  end

  it "wraps content in a Stimulus dialog controller" do
    expect(rendered.css("[data-controller='dialog']")).to be_present
  end

  it "renders a trigger button that opens the dialog" do
    btn = rendered.css("button[data-action='dialog#open']").first
    expect(btn).to be_present
    expect(btn.text.strip).to eq("Delete")
  end

  it "renders the dialog element with the dialog target" do
    expect(rendered.css("dialog[data-dialog-target='dialog']")).to be_present
  end

  it "renders the dialog title" do
    expect(rendered.css("p.dialog-title").text.strip).to eq("Delete this item?")
  end

  it "renders the cancel button wired to dialog#close" do
    cancel = rendered.css("button[data-action='dialog#close']").first
    expect(cancel).to be_present
    expect(cancel.text.strip).to eq("Cancel")
  end

  it "renders the confirm_action slot" do
    expect(rendered.css("button#confirm-btn")).to be_present
  end

  context "with danger variant (default)" do
    it "applies red styling to the trigger button" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).to include("text-red-600")
    end
  end

  context "with neutral variant" do
    let(:component) do
      described_class.new(label: "Detach", dialog_title: "Detach action?", variant: :neutral)
    end

    it "applies neutral styling to the trigger button" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).to include("text-gray-600")
    end
  end

  context "with primary variant" do
    let(:component) do
      described_class.new(label: "Run", dialog_title: "Run pipeline?", variant: :primary)
    end

    it "applies indigo styling to the trigger button" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).to include("bg-indigo-600")
    end
  end

  context "with optional body content" do
    subject(:rendered) do
      render_inline(component) do |c|
        c.with_confirm_action { "".html_safe }
        c.with_body { "<p id='body-text'>Are you really sure?</p>".html_safe }
      end
    end

    it "renders the body slot inside the dialog" do
      expect(rendered.css("p#body-text")).to be_present
    end
  end

  context "with a button_class override" do
    let(:component) do
      described_class.new(
        label: "×",
        dialog_title: "Detach?",
        button_class: "ml-1 text-gray-400 hover:text-red-500 bg-transparent border-0 cursor-pointer p-0 font-bold"
      )
    end

    it "uses the given button_class instead of variant classes" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).to eq("ml-1 text-gray-400 hover:text-red-500 bg-transparent border-0 cursor-pointer p-0 font-bold")
    end

    it "does not apply variant-based classes" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).not_to include("text-red-600")
    end
  end

  context "with a custom cancel label" do
    let(:component) do
      described_class.new(label: "Remove", dialog_title: "Remove step?", cancel_label: "No, keep it")
    end

    it "renders the custom cancel label" do
      cancel = rendered.css("button[data-action='dialog#close']").first
      expect(cancel.text.strip).to eq("No, keep it")
    end
  end
end
