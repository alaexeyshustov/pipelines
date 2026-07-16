
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ServiceMustHaveInstanceCall, :config do
  context "when in a service file" do
    let(:file) { "app/services/foo_service.rb" }

    it "registers an offense when def call is missing" do
      expect_offense(<<~RUBY, file)
        class FooService
        ^^^^^^^^^^^^^^^^ Service classes must define `def call`.
          def self.call; end
        end
      RUBY
    end

    it "registers no offense when def call is present" do
      expect_no_offenses(<<~RUBY, file)
        class FooService
          def self.call; end
          def call; end
        end
      RUBY
    end
  end

  context "when outside a service file" do
    it "registers no offense" do
      expect_no_offenses(<<~RUBY, "app/models/foo.rb")
        class Foo; end
      RUBY
    end
  end
end
