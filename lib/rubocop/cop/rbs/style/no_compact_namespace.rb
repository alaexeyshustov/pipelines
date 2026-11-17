module RuboCop
  module Cop
    module RBS
      module Style
        # Disallows compact `class A::B` / `module A::B` declarations in RBS.
        # Open each namespace as its own block, as the Ruby source does.
        #
        # @example
        #   # bad
        #   class Orchestration::Action
        #   end
        #
        #   # good
        #   module Orchestration
        #     class Action
        #     end
        #   end
        #
        class NoCompactNamespace < RuboCop::RBS::CopBase
          MSG = "Open full namespace blocks instead of a compact `%<name>s`."

          def on_rbs_class(decl)
            return if decl.name.namespace.path.empty?

            name_location = decl.location&.[](:name)
            add_offense(location_to_range(name_location), message: format(MSG, name: decl.name))
          end
          alias on_rbs_module on_rbs_class
        end
      end
    end
  end
end
