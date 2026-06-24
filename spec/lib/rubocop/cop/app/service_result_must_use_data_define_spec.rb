# frozen_string_literal: true

require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ServiceResultMustUseDataDefine, :config do
  let(:file) { "app/services/foo_service.rb" }

  it "registers an offense when Result uses Struct.new" do
    expect_offense(<<~RUBY, file)
      class FooService
        Result = Struct.new(:ok, :value)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Data.define` instead of `Struct.new` for Result value objects.
      end
    RUBY
  end

  it "registers no offense when Result uses Data.define" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        Result = Data.define(:ok, :value)
      end
    RUBY
  end

  it "registers no offense for non-Result Struct constants" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        Config = Struct.new(:host, :port)
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
