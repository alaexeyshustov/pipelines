# frozen_string_literal: true

module UI
  class LabelComponent < ApplicationComponent
    BASE = "flex items-center gap-2 text-sm leading-none font-medium select-none " \
           "group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:opacity-50 " \
           "peer-disabled:cursor-not-allowed peer-disabled:opacity-50"

    def initialize(text = nil, for: nil, **html_attrs)
      @text = text || html_attrs.delete(:label)
      @for = binding.local_variable_get(:for)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:label, content.presence || @text,
        class: cn(BASE, @extra_class),
        for: @for,
        **@html_attrs)
    end
  end
end
