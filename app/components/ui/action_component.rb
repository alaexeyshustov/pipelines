# frozen_string_literal: true

module UI
  class ActionComponent < ViewComponent::Base
    TYPES = %i[link button delete dialog raw].freeze

    # Per-variant border + colour tokens (background handled per-token)
    VARIANT_CLASSES = {
      primary:   "bg-indigo-600 text-white hover:bg-indigo-700 border-indigo-600",
      secondary: "bg-transparent text-indigo-600 border-indigo-200 hover:bg-indigo-50 hover:text-indigo-800",
      neutral:   "bg-transparent text-gray-600 border-gray-200 hover:bg-gray-50",
      danger:    "bg-transparent text-red-600 border-red-200 hover:bg-red-50 hover:text-red-800",
      success:   "bg-transparent text-green-600 border-green-200 hover:bg-green-50"
    }.freeze

    # Solid confirm button colour per variant (used inside the dialog)
    CONFIRM_VARIANT_CLASSES = {
      primary:   "bg-indigo-600 text-white hover:bg-indigo-700",
      secondary: "bg-indigo-600 text-white hover:bg-indigo-700",
      neutral:   "bg-gray-600 text-white hover:bg-gray-700",
      danger:    "bg-red-600 text-white hover:bg-red-700",
      success:   "bg-green-600 text-white hover:bg-green-700"
    }.freeze

    BASE_CLASSES   = "px-4 py-2 text-sm font-medium rounded-lg transition-colors border"
    LINK_CLASSES   = "px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700 transition-colors"
    BUTTON_CLASSES = "px-4 py-2 bg-white text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 transition-colors border border-gray-300"
    DELETE_CLASSES = "px-4 py-2 bg-red-50 text-red-600 text-sm font-medium rounded-lg hover:bg-red-100 transition-colors border-0 cursor-pointer"

    def initialize(type: :raw, label: nil, url: nil, confirm: nil, method: nil,
                   variant: nil, dialog_title: nil, confirm_label: nil, size: :sm,
                   body_component: nil, body_options: {})
      @type           = type.to_sym
      @label          = label
      @url            = url
      @confirm        = confirm
      @confirm_label  = confirm_label || confirm
      @method         = method
      @variant        = variant&.to_sym
      @dialog_title   = dialog_title
      @size           = size
      @body_component = body_component
      @body_options   = body_options || {}
    end

    def call
      subcomponent.render_in(view_context)
    end

    private

    def subcomponent # rubocop:disable Metrics/MethodLength
      case @type
      when :link
        LinkComponent.new(label: @label, url: @url, variant: @variant)
      when :button
        ButtonComponent.new(label: @label, url: @url, method: @method, variant: @variant)
      when :delete
        DeleteComponent.new(label: @label, url: @url, confirm: @confirm)
      when :dialog
        DialogComponent.new(
          label: @label, dialog_title: @dialog_title,
          url: @url, method: @method,
          confirm_label: @confirm_label,
          variant: @variant,
          size: @size,
          body_component: @body_component,
          body_options: @body_options
        )
      when :raw
        RawComponent.new.with_content(content)
      else
        raise ArgumentError, "Unknown action type: #{@type.inspect}. Must be one of #{TYPES.inspect}"
      end
    end
  end
end
