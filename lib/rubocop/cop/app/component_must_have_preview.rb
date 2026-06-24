# frozen_string_literal: true

module RuboCop
  module Cop
    module App
      # Each *_component.rb must have a corresponding *_component_preview.rb.
      class ComponentMustHavePreview < Base
        MSG = "Missing preview file for this component: expected `%<path>s`."

        def on_class(node)
          return unless component_file?
          return if node.each_ancestor(:class).any?

          preview_path = derive_preview_path
          return if preview_path.nil?
          return if File.exist?(preview_path)

          declaration = node.loc.keyword.join(node.parent_class&.source_range || node.loc.name)
          add_offense(declaration, message: format(MSG, path: preview_path))
        end

        private

        def component_file?
          path = processed_source.path
          path.include?("app/components/") && path.end_with?("_component.rb")
        end

        def derive_preview_path
          path = processed_source.path
          match = path.match(%r{(.*)/app/components/(.*_component)\.rb$})
          return unless match

          "#{match[1]}/spec/components/previews/#{match[2]}_preview.rb"
        end
      end
    end
  end
end
