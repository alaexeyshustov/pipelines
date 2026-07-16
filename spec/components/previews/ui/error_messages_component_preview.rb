
module UI
  class ErrorMessagesComponentPreview < ViewComponent::Preview
    def with_errors
      errors = ActiveModel::Errors.new(OpenStruct.new)
      errors.add(:base, "Name can't be blank")
      errors.add(:base, "Email is invalid")
      render(UI::ErrorMessagesComponent.new(errors: errors))
    end

    def single_error
      errors = ActiveModel::Errors.new(OpenStruct.new)
      errors.add(:base, "Something went wrong")
      render(UI::ErrorMessagesComponent.new(errors: errors))
    end
  end
end
