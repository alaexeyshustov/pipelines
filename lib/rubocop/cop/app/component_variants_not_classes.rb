module RuboCop
  module Cop
    module App
      # Components take a `variant:` rather than CSS classes from the caller.
      class ComponentVariantsNotClasses < Base
        MSG = "Use a `variant:` instead of passing CSS classes into a component."
        CLASS_KEYWORDS = %i[class classes css_class css_classes html_class html_classes].freeze

        def on_def(node)
          return unless component_file?
          return unless node.method_name == :initialize

          node.arguments.each do |argument|
            next unless argument.kwarg_type? || argument.kwoptarg_type?
            next unless CLASS_KEYWORDS.include?(argument.name)

            add_offense(argument, message: MSG)
          end
        end

        private

        def component_file?
          processed_source.path.include?("app/components/")
        end
      end
    end
  end
end
