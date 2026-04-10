# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::ActionComponent, type: :component do
  describe ":link type" do
    subject(:rendered) { render_inline(described_class.new(type: :link, label: "Edit", url: "/interviews/1/edit")) }

    it "renders an anchor tag with the correct label and url" do
      link = rendered.css("a").first
      expect(link.text.strip).to eq("Edit")
      expect(link["href"]).to eq("/interviews/1/edit")
    end

    it "applies primary indigo styling by default" do
      link = rendered.css("a").first
      expect(link["class"]).to include("bg-indigo-600")
      expect(link["class"]).to include("text-white")
    end

    context "with variant: :secondary" do
      subject(:rendered) { render_inline(described_class.new(type: :link, label: "Edit", url: "/edit", variant: :secondary)) }

      it "renders an outline indigo link" do
        link = rendered.css("a").first
        expect(link["class"]).to include("text-indigo-600")
        expect(link["class"]).to include("border-indigo-200")
      end
    end

    context "with variant: :ghost" do
      subject(:rendered) { render_inline(described_class.new(type: :link, label: "History", url: "/history", variant: :ghost)) }

      it "renders a plain muted text link" do
        link = rendered.css("a").first
        expect(link["class"]).to include("text-gray-500")
        expect(link["class"]).not_to include("border")
      end
    end
  end

  describe ":button type" do
    subject(:rendered) { render_inline(described_class.new(type: :button, label: "Submit", url: "/run", method: :post)) }

    it "renders a form with a submit button" do
      expect(rendered.css("form")).to be_present
      expect(rendered.css("button[type='submit']").text.strip).to eq("Submit")
    end

    it "applies button styling to the submit button by default" do
      btn = rendered.css("button[type='submit']").first
      expect(btn["class"]).to include("text-gray-700")
    end

    context "with variant: :success" do
      subject(:rendered) { render_inline(described_class.new(type: :button, label: "Enable", url: "/toggle", method: :patch, variant: :success)) }

      it "applies green styling" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["class"]).to include("text-green-600")
        expect(btn["class"]).to include("border-green-200")
      end
    end

    context "with variant: :neutral" do
      subject(:rendered) { render_inline(described_class.new(type: :button, label: "Disable", url: "/toggle", method: :patch, variant: :neutral)) }

      it "applies neutral gray styling" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["class"]).to include("text-gray-600")
        expect(btn["class"]).to include("border-gray-200")
      end
    end

    context "with confirm:" do
      subject(:rendered) do
        render_inline(UI::ActionComponent::ButtonComponent.new(
          label: "Archive", url: "/archive", confirm: "Are you sure?"
        ))
      end

      it "sets turbo-confirm on the button" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["data-turbo-confirm"]).to eq("Are you sure?")
      end
    end

    context "with data: attributes" do
      subject(:rendered) do
        render_inline(UI::ActionComponent::ButtonComponent.new(
          label: "Submit", url: "/submit",
          data: { action: "batch#batchSubmit", "batch-batch-action-param": "archive" }
        ))
      end

      it "passes data attributes to the button" do
        btn = rendered.css("button[type='submit']").first
        expect(btn["data-action"]).to eq("batch#batchSubmit")
        expect(btn["data-batch-batch-action-param"]).to eq("archive")
      end
    end
  end

  describe ":delete type" do
    subject(:rendered) do
      render_inline(described_class.new(type: :delete, label: "Delete", url: "/interviews/1",
                                        confirm: "Delete this interview record?"))
    end

    it "renders a form targeting the correct url" do
      form = rendered.css("form").first
      expect(form["action"]).to eq("/interviews/1")
    end

    it "sets turbo confirm on the form" do
      form = rendered.css("form").first
      expect(form["data-turbo-confirm"]).to eq("Delete this interview record?")
    end

    it "applies delete (red) styling to the submit button" do
      btn = rendered.css("button[type='submit']").first
      expect(btn["class"]).to include("text-red-600")
      expect(btn["class"]).to include("bg-red-50")
    end
  end

  describe "UI::ActionComponent::DialogComponent body slot" do
    context "with non-post method (no form builder)" do
      subject(:rendered) do
        component = UI::ActionComponent::DialogComponent.new(
          label: "Delete",
          dialog_title: "Are you sure?",
          url: "/records/1",
          method: :delete,
          confirm_label: "Yes, delete",
          variant: :danger
        )
        component.with_body { "<p id='body-content'>Extra info</p>".html_safe }
        render_inline(component)
      end

      it "renders the body content inside the dialog" do
        expect(rendered.css("dialog #body-content")).to be_present
      end

      it "wraps body in a mb-4 div" do
        expect(rendered.css("dialog .mb-4").first).to be_present
      end
    end

    context "with method: :post (form builder yielded)" do
      subject(:rendered) do
        component = UI::ActionComponent::DialogComponent.new(
          label: "Run",
          dialog_title: "Run pipeline?",
          url: "/pipelines/1/run",
          method: :post,
          confirm_label: "Run",
          variant: :primary
        )
        component.with_body do |f|
          f.text_field(:name, placeholder: "Pipeline name", class: "field-input").html_safe
        end
        render_inline(component)
      end

      it "renders the body inside the form" do
        expect(rendered.css("dialog form .mb-4 input[name='name']")).to be_present
      end

      it "body receives the form builder (input is wired to the form)" do
        input = rendered.css("dialog form input[name='name']").first
        expect(input["placeholder"]).to eq("Pipeline name")
      end
    end
  end

  describe ":dialog type" do
    subject(:rendered) do
      render_inline(described_class.new(
        type: :dialog,
        label: "Delete",
        dialog_title: "Are you sure?",
        url: "/records/1",
        method: :delete,
        confirm: "Yes, delete",
        variant: :danger
      ))
    end

    it "wraps content in a Stimulus dialog controller" do
      expect(rendered.css("[data-controller='dialog']")).to be_present
    end

    it "renders a trigger button that opens the dialog" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn).to be_present
      expect(btn.text.strip).to eq("Delete")
    end

    it "renders a <dialog> element with the given title" do
      dialog = rendered.css("dialog").first
      expect(dialog).to be_present
      expect(dialog.css("h2.dialog-title").text.strip).to eq("Are you sure?")
    end

    it "renders a cancel button that closes the dialog" do
      cancel = rendered.css("button[data-action='dialog#close']").first
      expect(cancel).to be_present
      expect(cancel.text.strip).to eq("Cancel")
    end

    it "renders a confirm form targeting the url" do
      form = rendered.css("dialog form").first
      expect(form["action"]).to eq("/records/1")
    end

    it "applies danger variant styling to the trigger button" do
      btn = rendered.css("button[data-action='dialog#open']").first
      expect(btn["class"]).to include("text-red-600")
      expect(btn["class"]).to include("border-red-200")
    end

    it "applies solid danger styling to the confirm button" do
      btn = rendered.css("dialog button[type='submit']").first
      expect(btn["class"]).to include("bg-red-600")
      expect(btn["class"]).to include("text-white")
    end

    context "with size: :md" do
      subject(:rendered) do
        render_inline(UI::ActionComponent::DialogComponent.new(
          label: "Run",
          dialog_title: "Run pipeline?",
          url: "/pipelines/1/run",
          method: :post,
          confirm_label: "Run",
          variant: :primary,
          size: :md
        ))
      end

      it "applies max-w-md to the dialog element" do
        dialog = rendered.css("dialog").first
        expect(dialog["class"]).to include("max-w-md")
      end
    end

    context "when method is :post" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :dialog,
          label: "Run",
          dialog_title: "Run pipeline?",
          url: "/pipelines/1/run",
          method: :post,
          confirm: "Run",
          variant: :primary
        ))
      end

      it "renders a form_with form targeting the url" do
        form = rendered.css("dialog form").first
        expect(form).to be_present
        expect(form["action"]).to eq("/pipelines/1/run")
      end

      it "renders the submit button inside the form" do
        expect(rendered.css("dialog form button[type='submit']")).to be_present
      end

      it "renders exactly one form inside the dialog" do
        expect(rendered.css("dialog form").count).to eq(1)
      end
    end
  end

  describe "UI::ActionComponent::DialogComponent body_component:" do
    let(:schema) do
      {
        "properties" => { "name" => { "type" => "string" } },
        "required"   => [ "name" ]
      }
    end

    context "with body_component: and method: :post" do
      subject(:rendered) do
        render_inline(UI::ActionComponent::DialogComponent.new(
          label: "Run",
          dialog_title: "Run pipeline?",
          url: "/pipelines/1/run",
          method: :post,
          confirm_label: "Run",
          variant: :primary,
          body_component: UI::JsonFieldsComponent,
          body_options: { schema: schema, name_prefix: "initial_input" }
        ))
      end

      it "renders the body inside the dialog form" do
        expect(rendered.css("dialog form .mb-4")).to be_present
      end

      it "renders an input for the schema field" do
        expect(rendered.css("dialog form input[name='initial_input[name]']")).to be_present
      end
    end

    context "when passed through ActionComponent with type: :dialog" do
      subject(:rendered) do
        render_inline(described_class.new(
          type: :dialog,
          label: "Run",
          dialog_title: "Run pipeline?",
          url: "/pipelines/1/run",
          method: :post,
          confirm: "Run",
          variant: :primary,
          body_component: UI::JsonFieldsComponent,
          body_options: { schema: schema, name_prefix: "initial_input" }
        ))
      end

      it "renders the body component inside the dialog form" do
        expect(rendered.css("dialog form input[name='initial_input[name]']")).to be_present
      end
    end
  end

  describe ":raw type (default — renders block content)" do
    subject(:rendered) do
      render_inline(described_class.new) { '<span id="custom-action">Custom</span>'.html_safe }
    end

    it "renders the yielded block content" do
      expect(rendered.css("span#custom-action")).to be_present
      expect(rendered.css("span#custom-action").text).to eq("Custom")
    end
  end
end
