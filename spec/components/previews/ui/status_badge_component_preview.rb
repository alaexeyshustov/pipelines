# frozen_string_literal: true

module UI
  class StatusBadgeComponentPreview < ViewComponent::Preview
    # @param label text
    # @param variant select [success, warning, danger, info, neutral]
    def default(label: "Active", variant: "success")
      render(UI::StatusBadgeComponent.new(label: label, variant: variant.to_sym))
    end

    def all_variants
      render_with_template(template: "ui/status_badge_component_preview/all_variants")
    end
  end
end
