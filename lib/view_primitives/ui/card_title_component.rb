# frozen_string_literal: true

module UI
  class CardTitleComponent < ApplicationComponent
    BASE = "leading-none font-semibold"

    def initialize(title = nil, **html_attrs)
      @title = title || html_attrs.delete(:label) || html_attrs.delete(:title)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:h3, content.presence || @title, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
