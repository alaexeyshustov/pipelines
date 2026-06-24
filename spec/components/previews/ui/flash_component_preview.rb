# frozen_string_literal: true

module UI
  class FlashComponentPreview < ViewComponent::Preview
    def notice
      render(UI::FlashComponent.new(flash: { "notice" => "Record saved successfully." }))
    end

    def alert
      render(UI::FlashComponent.new(flash: { "alert" => "Something went wrong." }))
    end

    def multiple
      render(UI::FlashComponent.new(flash: {
        "notice" => "Changes saved.",
        "alert"  => "Some fields may need review."
      }))
    end

    def empty
      render(UI::FlashComponent.new(flash: {}))
    end
  end
end
