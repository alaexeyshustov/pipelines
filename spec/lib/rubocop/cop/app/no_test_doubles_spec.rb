
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoTestDoubles, :config do
  let(:file) { "spec/services/foo_service_spec.rb" }

  it "registers an offense for double" do
    expect_offense(<<~RUBY, file)
      let(:dep) { double(:dep) }
                  ^^^^^^^^^^^^ Do not use `double`; use real objects or fake implementations instead.
    RUBY
  end

  it "registers an offense for instance_double" do
    expect_offense(<<~RUBY, file)
      let(:dep) { instance_double(Foo) }
                  ^^^^^^^^^^^^^^^^^^^^ Do not use `instance_double`; use real objects or fake implementations instead.
    RUBY
  end

  it "registers an offense for spy" do
    expect_offense(<<~RUBY, file)
      let(:dep) { spy(:dep) }
                  ^^^^^^^^^ Do not use `spy`; use real objects or fake implementations instead.
    RUBY
  end

  it "registers no offense outside spec files" do
    expect_no_offenses(<<~RUBY, "app/services/foo_service.rb")
      class Foo
        def call
          double
        end
      end
    RUBY
  end
end
