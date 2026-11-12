module UI
  # A pill-shaped link used for preset filters; +active+ marks the selected one.
  class FilterChipComponent < ViewComponent::Base
    BASE_CLASSES = "inline-block px-3 py-1 rounded-full text-sm border"
    VARIANT_CLASSES = {
      true => "bg-indigo-600 border-indigo-600 text-white",
      false => "bg-white border-gray-300 text-gray-700 hover:bg-gray-50"
    }.freeze

    def initialize(label:, href:, active: false)
      @label = label
      @href = href
      @active = active
    end

    def call
      link_to @label, @href, class: "#{BASE_CLASSES} #{VARIANT_CLASSES.fetch(@active)}", "aria-current": (@active ? "true" : nil)
    end
  end
end
