
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoCurrentInComponent, :config do
  let(:file) { "app/components/ui/foo_component.rb" }

  it "registers an offense for Current.user access" do
    expect_offense(<<~RUBY, file)
      class FooComponent < ViewComponent::Base
        def render?
          Current.user.present?
          ^^^^^^^^^^^^ Do not access `Current` inside a component; inject the value through the constructor instead.
        end
      end
    RUBY
  end

  it "registers no offense when Current is not accessed" do
    expect_no_offenses(<<~RUBY, file)
      class FooComponent < ViewComponent::Base
        def initialize(user:)
          @user = user
        end
      end
    RUBY
  end

  it "registers no offense in a preview file" do
    expect_no_offenses(<<~RUBY, "app/components/ui/foo_component_preview.rb")
      class FooComponentPreview
        def default
          Current.user
        end
      end
    RUBY
  end

  it "registers no offense outside component files" do
    expect_no_offenses(<<~RUBY, "app/helpers/foo_helper.rb")
      module FooHelper
        def greet
          Current.user.name
        end
      end
    RUBY
  end
end
