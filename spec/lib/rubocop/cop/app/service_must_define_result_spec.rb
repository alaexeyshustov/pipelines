require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ServiceMustDefineResult, :config do
  let(:file) { "app/services/foo_service.rb" }

  it "registers an offense when a service defines no Result" do
    expect_offense(<<~RUBY, file)
      class FooService
      ^^^^^^^^^^^^^^^^ Services must define `Result = Data.define(...)` and return it.
        def self.call
          new.call
        end
      end
    RUBY
  end

  it "registers an offense and autocorrects when Result uses Struct.new" do
    expect_offense(<<~RUBY, file)
      Result = Struct.new(:ok, :value)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Define `Result` with `Data.define`, not `Struct.new`.
    RUBY

    expect_correction(<<~RUBY)
      Result = Data.define(:ok, :value)
    RUBY
  end

  it "registers no offense when Result uses Data.define" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        Result = Data.define(:ok, :value)
      end
    RUBY
  end

  it "registers no offense for a namespaced service with a Result" do
    expect_no_offenses(<<~RUBY, file)
      module Foo
        class Bar
          Result = Data.define(:ok)
        end
      end
    RUBY
  end

  it "registers no offense for nested classes and error classes" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        Result = Data.define(:ok)
        Error = Class.new(StandardError)

        class Row
        end
      end

      class BarError < StandardError
      end
    RUBY
  end

  it "registers no offense outside service files" do
    expect_no_offenses(<<~RUBY, "app/models/foo.rb")
      class Foo
        Result = Struct.new(:ok)
      end
    RUBY
  end
end
