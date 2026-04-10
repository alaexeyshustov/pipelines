# frozen_string_literal: true

module UI
  class DetailCardComponent < ViewComponent::Base
    renders_one :status_badge, "UI::StatusBadgeComponent"

    Attribute = Data.define(:label, :attribute, :type, :variant_map)
    class Attribute
      def self.from(hash)
        new(
          label:       hash.fetch(:label),
          attribute:   hash.fetch(:attribute),
          type:        hash.fetch(:type, :text),
          variant_map: hash.fetch(:variant_map, {})
        )
      end
    end

    def initialize(entity:, attributes:)
      @entity     = entity
      @attributes = attributes.map { Attribute.from(_1) }
    end

    def value_for(attr)
      @entity.public_send(attr.attribute)
    end

    def variant_for(attr, value)
      attr.variant_map.fetch(value.to_s, :neutral)
    end

    def text_classes_for(attr)
      classes = "text-sm text-gray-900"
      classes += " tabular-nums" if attr.type == :date
      classes += " font-mono"    if attr.type == :mono
      classes
    end

    def json_display(val)
      val.present? ? JSON.pretty_generate(val) : "—"
    end
  end
end
