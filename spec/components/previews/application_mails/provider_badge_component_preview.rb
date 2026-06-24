# frozen_string_literal: true

module ApplicationMails
  class ProviderBadgeComponentPreview < ViewComponent::Preview
    def gmail
      render(ApplicationMails::ProviderBadgeComponent.new(status: "gmail"))
    end

    def unknown_provider
      render(ApplicationMails::ProviderBadgeComponent.new(status: "yahoo"))
    end
  end
end
