module RuboCop
  module Cop
    module RBS
      module Lint
        # Disallows `untyped` in RBS signatures. Every use of `untyped` opts
        # out of type checking for that position — prefer a concrete type, a
        # union, or a generic parameter instead. A bare `Array` or `Hash` is
        # `untyped` in disguise, so their element types must be given.
        #
        # @example
        #   # bad
        #   def fetch: () -> untyped
        #   def store: (untyped value) -> void
        #   def ids: () -> Array[untyped]
        #   def names: () -> Array
        #   MAPPING: Hash[String, untyped]
        #
        #   # good
        #   def fetch: () -> String
        #   def store: (String value) -> void
        #   def ids: () -> Array[Integer]
        #   MAPPING: Hash[String, Integer]
        #
        class NoUntyped < RuboCop::RBS::CopBase
          MSG = "Avoid `untyped`. Use a more specific type.".freeze
          BARE_COLLECTION_MSG = "Give the element types, e.g. `Array[String]` or `Hash[Symbol, Integer]`.".freeze
          COLLECTIONS = %i[Array Hash].freeze

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
            on_type([ ::RBS::Types::ClassInstance ], type) do |instance|
              next unless instance.is_a?(::RBS::Types::ClassInstance) && bare_collection?(instance)

              add_offense(location_to_range(instance.location), message: BARE_COLLECTION_MSG)
            end
          end

          def bare_collection?(instance)
            instance.args.empty? && COLLECTIONS.include?(instance.name.name) && instance.name.namespace.path.empty?
          end
        end
      end
    end
  end
end
