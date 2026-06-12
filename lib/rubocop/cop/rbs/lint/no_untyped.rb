# frozen_string_literal: true

module RuboCop
  module Cop
    module RBS
      module Lint
        # Disallows `untyped` in RBS signatures. Every use of `untyped` opts
        # out of type checking for that position — prefer a concrete type, a
        # union, or a generic parameter instead.
        #
        # @example
        #   # bad
        #   def fetch: () -> untyped
        #   def store: (untyped value) -> void
        #   def ids: () -> Array[untyped]
        #   MAPPING: Hash[String, untyped]
        #
        #   # good
        #   def fetch: () -> String
        #   def store: (String value) -> void
        #   def ids: () -> Array[Integer]
        #   MAPPING: Hash[String, Integer]
        #
        class NoUntyped < RuboCop::RBS::CopBase
          MSG = "Avoid `untyped`. Use a more specific type."

          def on_rbs_def(decl)
            decl.overloads.each do |overload|
              overload.method_type.each_type do |type|
                check_type(type)
              end
            end
          end

          def on_rbs_constant(decl)
            check_type(decl.type)
          end
          alias on_rbs_global on_rbs_constant
          alias on_rbs_type_alias on_rbs_constant
          alias on_rbs_attribute on_rbs_constant
          alias on_rbs_var on_rbs_constant

          private

          def check_type(type)
            on_type([ ::RBS::Types::Bases::Any ], type) do |untyped|
              add_offense(location_to_range(untyped.location), message: MSG)
            end
          end
        end
      end
    end
  end
end
