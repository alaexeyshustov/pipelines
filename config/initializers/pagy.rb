# Load the full series_nav helper chain (series, page_label, a_lambda, etc.)
# before overriding series_nav with our Tailwind version.
require "pagy/toolbox/helpers/series_nav"

Pagy::OPTIONS[:limit] = 20

class Pagy
  module NumericHelpers
    # Tailwind-styled pagination bar.
    # Uses page_url (lazy-loaded via HelperLoader) instead of a_lambda so no
    # extra requires are needed — a_lambda is only available after series_nav.rb
    # is required, which this override intentionally bypasses.
    def series_nav(style = nil, **)
      return send(:"#{style}_series_nav", **) if style && style.to_s != "pagy"
      return "" if last == 1

      base    = "inline-flex items-center justify-center min-w-[2rem] h-8 px-2.5 text-sm rounded-lg border transition-colors"
      active  = "#{base} border-indigo-500 bg-indigo-500 text-white font-medium cursor-default"
      normal  = "#{base} border-gray-300 text-gray-600 hover:bg-gray-50 hover:border-gray-400"
      ghost   = "#{base} border-transparent text-gray-400 cursor-not-allowed"
      gap_cls = "inline-flex items-center justify-center min-w-[2rem] h-8 px-1 text-sm text-gray-400 select-none"

      prev_text  = I18n.translate("pagy.previous")
      next_text  = I18n.translate("pagy.next")
      prev_label = I18n.translate("pagy.aria_label.previous")
      next_label = I18n.translate("pagy.aria_label.next")

      html = if previous
               %(<a href="#{page_url(previous)}" rel="prev" aria-label="#{prev_label}" class="#{normal}">#{prev_text}</a>)
      else
               %(<a role="link" aria-disabled="true" aria-label="#{prev_label}" class="#{ghost}">#{prev_text}</a>)
      end

      series(**).each do |item|
        html << case item
        when Integer
                  %(<a href="#{page_url(item)}" class="#{normal}">#{page_label(item)}</a>)
        when String
                  %(<a role="link" aria-disabled="true" aria-current="page" class="#{active}">#{page_label(item)}</a>)
        when :gap
                  %(<a role="separator" aria-disabled="true" class="#{gap_cls}">#{I18n.translate('pagy.gap')}</a>)
        else
                  raise InternalError, "unexpected series item: #{item.inspect}"
        end
      end

      html << if self.next
                %(<a href="#{page_url(self.next)}" rel="next" aria-label="#{next_label}" class="#{normal}">#{next_text}</a>)
      else
                %(<a role="link" aria-disabled="true" aria-label="#{next_label}" class="#{ghost}">#{next_text}</a>)
      end

      %(<nav class="flex items-center gap-1 mt-6 justify-center" aria-label="Pages">#{html}</nav>)
    end
  end
end
