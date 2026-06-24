# frozen_string_literal: true

require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ServiceSinglePublicMethod, :config do
  let(:file) { "app/services/foo_service.rb" }

  it "registers an offense for a public method other than call/initialize" do
    expect_offense(<<~RUBY, file)
      class FooService
        def call; end
        def helper
        ^^^^^^^^^^ Service public instance methods must be limited to `call` and `initialize`; `helper` is not allowed.
        end
      end
    RUBY
  end

  it "registers no offense for call and initialize" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        def initialize(x:); end
        def call; end
      end
    RUBY
  end

  it "registers no offense for private methods" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        def call; end

        private

        def helper; end
        def another; end
      end
    RUBY
  end

  it "registers no offense outside service files" do
    expect_no_offenses(<<~RUBY, "app/models/foo.rb")
      class Foo
        def helper; end
      end
    RUBY
  end
end
