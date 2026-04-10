# frozen_string_literal: true

module UI
  class DialogComponent < ViewComponent::Base
    renders_one :confirm_action
    renders_one :body

    VARIANTS = {
      danger:  "text-red-600 hover:text-red-800 border-red-200 hover:bg-red-50",
      neutral: "text-gray-600 border-gray-200 hover:bg-gray-50",
      primary: "text-white bg-indigo-600 hover:bg-indigo-700 border-indigo-600"
    }.freeze

    def initialize(label:, dialog_title:, variant: :danger, cancel_label: "Cancel", button_class: nil)
      @label        = label
      @dialog_title = dialog_title
      @variant      = variant.to_sym
      @cancel_label = cancel_label
      @button_class = button_class
    end

    def trigger_classes
      return @button_class if @button_class

      base = "px-4 py-2 text-sm font-medium border rounded-lg transition-colors bg-transparent cursor-pointer"
      "#{base} #{VARIANTS.fetch(@variant, VARIANTS[:neutral])}"
    end
  end
end
