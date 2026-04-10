# frozen_string_literal: true

module UI
  class JsonDisclosureComponent < ViewComponent::Base
    def initialize(label:, data:)
      @label = label
      @data  = data
    end

    def render?
      @data.present?
    end

    def pretty_json
      JSON.pretty_generate(@data)
    end
  end
end
