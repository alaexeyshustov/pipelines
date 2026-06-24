# frozen_string_literal: true

module UI
  class JsonDisclosureComponentPreview < ViewComponent::Preview
    def default
      render(UI::JsonDisclosureComponent.new(
        label: "Output",
        data: { "classification" => "offer", "confidence" => 0.92, "label" => "Job Offer" }
      ))
    end

    def nested
      render(UI::JsonDisclosureComponent.new(
        label: "Diagnostics",
        data: { "error" => "Timeout", "retries" => 3, "context" => { "model" => "claude-sonnet-4-6" } }
      ))
    end

    def empty
      render(UI::JsonDisclosureComponent.new(label: "Input", data: nil))
    end
  end
end
