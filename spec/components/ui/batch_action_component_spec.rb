# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::BatchActionComponent, type: :component do
  describe ":button type" do
    subject(:rendered) do
      render_inline(described_class.new(
        type: :button,
        label: "Archive",
        url: "/interviews/batch",
        action: "archive",
        variant: :neutral
      ))
    end

    it "renders a form posting to the given url" do
      form = rendered.css("form[action='/interviews/batch']").first
      expect(form).to be_present
      expect(form["method"]).to eq("post")
    end

    it "renders a submit button wired to batch#batchSubmit" do
      btn = rendered.css("button[type='submit'][data-action='batch#batchSubmit']").first
      expect(btn).to be_present
      expect(btn.text.strip).to eq("Archive")
    end

    it "passes action as a Stimulus param" do
      btn = rendered.css("button[type='submit']").first
      expect(btn["data-batch-batch-action-param"]).to eq("archive")
    end

    it "defaults require-selection param to true" do
      btn = rendered.css("button[type='submit']").first
      expect(btn["data-batch-require-selection-param"]).to eq("true")
    end

    context "with confirm message" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :button,
          label: "Delete",
          url: "/interviews/batch",
          action: "delete",
          confirm: "Delete selected?"
        ))
      end

      it "passes confirm message as a Stimulus param" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["data-batch-confirm-msg-param"]).to eq("Delete selected?")
      end
    end

    context "with require_selection: false" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :button,
          label: "Export",
          url: "/interviews/batch",
          action: "export",
          require_selection: false
        ))
      end

      it "passes false as a Stimulus param" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["data-batch-require-selection-param"]).to eq("false")
      end
    end

    context "with variant: :danger" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :button,
          label: "Delete",
          url: "/interviews/batch",
          action: "delete",
          variant: :danger
        ))
      end

      it "applies danger variant styling" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["class"]).to include("text-red-600")
        expect(btn["class"]).to include("border-red-200")
      end
    end

    context "with variant: :primary" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :button,
          label: "Run",
          url: "/interviews/batch",
          action: "run",
          variant: :primary
        ))
      end

      it "applies primary variant styling" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["class"]).to include("bg-indigo-600")
        expect(btn["class"]).to include("text-white")
      end
    end
  end

  describe ":dialog type" do
    subject(:rendered) do
      render_inline(described_class.new(
        type: :dialog,
        label: "Archive Selected",
        dialog_title: "Archive interviews?",
        url: "/interviews/batch",
        action: "archive",
        confirm: "Archive",
        variant: :neutral
      ))
    end

    it "wraps content in a Stimulus dialog controller" do
      expect(rendered.css("[data-controller='dialog']")).to be_present
    end

    it "renders a trigger button that opens the dialog" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn).to be_present
      expect(btn.text.strip).to eq("Archive Selected")
    end

    it "renders a <dialog> element with the given title" do
      expect(rendered.css("dialog h2.dialog-title").text.strip).to eq("Archive interviews?")
    end

    it "renders a form targeting the batch url" do
      form = rendered.css("dialog form").first
      expect(form["action"]).to eq("/interviews/batch")
    end

    it "renders a cancel button that closes the dialog" do
      cancel = rendered.css("button[data-action='dialog#close']").first
      expect(cancel).to be_present
      expect(cancel.text.strip).to eq("Cancel")
    end

    it "renders a submit button with the confirm label" do
      btn = rendered.css("dialog form button[type='submit']").first
      expect(btn.text.strip).to eq("Archive")
    end

    it "applies neutral variant styling to the trigger button" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).to include("text-gray-600")
    end

    context "with variant: :danger" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :dialog,
          label: "Delete Selected",
          dialog_title: "Delete interviews?",
          url: "/interviews/batch",
          action: "delete",
          confirm: "Yes, delete",
          variant: :danger
        ))
      end

      it "applies danger variant styling to the trigger button" do
        btn = rendered.css("button[data-action='dialog#open']").first
        expect(btn["class"]).to include("text-red-600")
        expect(btn["class"]).to include("border-red-200")
      end

      it "applies solid danger styling to the confirm button" do
        btn = rendered.css("dialog form button[type='submit']").first
        expect(btn["class"]).to include("bg-red-600")
        expect(btn["class"]).to include("text-white")
      end
    end

    context "with size: :md" do
      subject(:rendered) do
        render_inline(UI::ActionComponent::DialogComponent.new(
          label: "Archive",
          dialog_title: "Archive?",
          url: "/batch",
          method: :post,
          size: :md
        ))
      end

      it "applies max-w-md to the dialog element" do
        expect(rendered.css("dialog").first["class"]).to include("max-w-md")
      end
    end

    context "with body block" do
      subject(:rendered) do
        component = UI::ActionComponent::DialogComponent.new(
          label: "Archive",
          dialog_title: "Archive?",
          url: "/batch",
          method: :post
        )
        component.with_body { "<p id='note'>This action is irreversible.</p>".html_safe }
        render_inline(component)
      end

      it "renders the body content inside the dialog" do
        expect(rendered.css("dialog #note")).to be_present
      end

      it "wraps the body in a mb-4 div" do
        expect(rendered.css("dialog .mb-4")).to be_present
      end
    end
  end

  describe ":raw type" do
    subject(:rendered) do
      render_inline(described_class.new(type: :raw)) { '<span id="custom-batch">Custom</span>'.html_safe }
    end

    it "renders the yielded block content" do
      expect(rendered.css("span#custom-batch")).to be_present
      expect(rendered.css("span#custom-batch").text).to eq("Custom")
    end
  end

  describe "unknown type" do
    it "raises ArgumentError" do
      expect {
        render_inline(described_class.new(type: :unknown))
      }.to raise_error(ArgumentError, /Unknown batch action type/)
    end
  end
end
