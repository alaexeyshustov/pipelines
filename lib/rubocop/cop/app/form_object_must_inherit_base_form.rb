
module RuboCop
  module Cop
    module App
      class FormObjectMustInheritBaseForm < Base
        MSG = "Form objects must inherit from `::BaseForm`."

        def on_class(node)
          return unless form_file?
          return if node.each_ancestor(:class).any?
          return if inherits_base_form?(node)

          add_offense(node, message: MSG)
        end

        private

        def form_file?
          processed_source.path.include?("app/forms/")
        end

        def inherits_base_form?(node)
          return true if node.identifier.short_name == :BaseForm

          parent = node.parent_class
          return false unless parent&.const_type?

          const_to_str(parent) == "BaseForm"
        end

        def const_to_str(node)
          return unless node&.const_type?

          namespace = node.namespace
          name = node.short_name.to_s
          return name if namespace.nil? || namespace.cbase_type?

          "#{const_to_str(namespace)}::#{name}"
        end
      end
    end
  end
end
