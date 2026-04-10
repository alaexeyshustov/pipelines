# frozen_string_literal: true

module ApplicationMails
  class ProviderBadgeComponent < UI::StatusBadgeComponent
    PROVIDER_VARIANTS = {
      "gmail" => :danger
    }.freeze

    def initialize(status:)
      super(
        label: status.to_s.capitalize,
        variant: PROVIDER_VARIANTS.fetch(status.to_s, :secondary)
      )
    end
  end
end
