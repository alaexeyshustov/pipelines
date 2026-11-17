require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ComponentVariantsNotClasses, :config do
  let(:file) { "app/components/ui/cell_component.rb" }

  it "registers an offense for a CSS class keyword in initialize" do
    expect_offense(<<~RUBY, file)
      class CellComponent
        def initialize(style: :default, classes: nil)
                                        ^^^^^^^^^^^^ Use a `variant:` instead of passing CSS classes into a component.
        end
      end
    RUBY
  end

  it "registers an offense for a required class keyword" do
    expect_offense(<<~RUBY, file)
      def initialize(css_class:)
                     ^^^^^^^^^^ Use a `variant:` instead of passing CSS classes into a component.
      end
    RUBY
  end

  it "registers no offense for variants, other methods or outside components" do
    expect_no_offenses(<<~RUBY, file)
      def initialize(variant: :primary, tool_classes: [])
      end

      def link_classes(classes: nil)
      end
    RUBY
    expect_no_offenses(<<~RUBY, "app/helpers/foo_helper.rb")
      def initialize(classes: nil)
      end
    RUBY
  end
end
