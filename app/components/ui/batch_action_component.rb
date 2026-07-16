
module UI
  class BatchActionComponent < ViewComponent::Base
    TYPES = %i[button dialog raw].freeze

    def initialize(type: :button, label: nil, url: nil, action: nil,
                   variant: nil, confirm: nil, dialog_title: nil,
                   require_selection: true)
      @type              = type.to_sym
      @label             = label
      @url               = url
      @action            = action
      @variant           = variant&.to_sym
      @confirm           = confirm
      @dialog_title      = dialog_title
      @require_selection = require_selection
    end

    def call
      subcomponent.render_in(view_context)
    end

    private

    def subcomponent
      case @type
      when :button then button_subcomponent
      when :dialog then dialog_subcomponent
      when :raw    then raw_subcomponent
      else
        raise ArgumentError, "Unknown batch action type: #{@type.inspect}. Must be one of #{TYPES.inspect}"
      end
    end

    def button_subcomponent
      ActionComponent::ButtonComponent.new(
        label: @label, url: @url, method: :post,
        variant: @variant || :neutral,
        data: {
          action: "batch#batchSubmit",
          "batch-batch-action-param": @action,
          "batch-confirm-msg-param": @confirm,
          "batch-require-selection-param": @require_selection
        }
      )
    end

    def dialog_subcomponent
      component = ActionComponent::DialogComponent.new(
        label: @label, dialog_title: @dialog_title,
        url: @url, method: :post,
        confirm_label: @confirm,
        variant: @variant
      )
      component.with_body { content } if content.present?
      component
    end

    def raw_subcomponent
      ActionComponent::RawComponent.new.with_content(content)
    end
  end
end
