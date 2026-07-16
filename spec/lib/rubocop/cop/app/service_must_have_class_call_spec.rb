
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ServiceMustHaveClassCall, :config do
  context "when in a service file" do
    let(:file) { "app/services/foo_service.rb" }

    it "registers an offense when def self.call is missing" do
      expect_offense(<<~RUBY, file)
        class FooService
        ^^^^^^^^^^^^^^^^ Service classes must define `def self.call`.
          def call; end
        end
      RUBY
    end

    it "registers no offense when def self.call is present" do
      expect_no_offenses(<<~RUBY, file)
        class FooService
          def self.call; end
          def call; end
        end
      RUBY
    end

    it "registers no offense for a nested class without def self.call" do
      expect_no_offenses(<<~RUBY, file)
        class FooService
          def self.call; end
          def call; end

          class Result; end
        end
      RUBY
    end

    it "registers no offense for a class that subclasses StandardError" do
      expect_no_offenses(<<~RUBY, "app/services/foo/bar_error.rb")
        module Foo
          class BarError < StandardError; end
        end
      RUBY
    end

    it "registers no offense when self.call is defined on a nested namespacing class" do
      expect_no_offenses(<<~RUBY, "app/services/foo/bar/validator.rb")
        module Foo
          class Bar
            class Validator
              def self.call(x); new(x).call; end
              def call; end
            end
          end
        end
      RUBY
    end
  end

  context "when outside a service file" do
    it "registers no offense" do
      expect_no_offenses(<<~RUBY, "app/models/foo.rb")
        class Foo
          def bar; end
        end
      RUBY
    end
  end
end
