# frozen_string_literal: true

module UI
  class StatusBadgeComponent < ViewComponent::Base
    VARIANT_CLASSES = {
      success:   "bg-green-50 text-green-700",
      warning:   "bg-yellow-50 text-yellow-700",
      danger:    "bg-red-50 text-red-700",
      info:      "bg-blue-50 text-blue-700",
      secondary: "bg-purple-50 text-purple-700",
      neutral:   "bg-gray-50 text-gray-700"
    }.freeze

    def initialize(label:, variant: :neutral)
      @label = label
      @variant = variant.to_sym
    end

    def classes
      VARIANT_CLASSES.fetch(@variant, VARIANT_CLASSES[:neutral])
    end
  end
end
