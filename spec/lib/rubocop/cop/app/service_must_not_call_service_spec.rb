# frozen_string_literal: true

require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::ServiceMustNotCallService, :config do
  let(:file) { "app/services/foo_service.rb" }

  it "registers an offense when calling another service via .call" do
    expect_offense(<<~RUBY, file)
      class FooService
        def call
          OtherService.call(x: 1)
          ^^^^^^^^^^^^^^^^^^^^^^^ Do not call another service's `.call` from within a service; use a job or orchestration service instead.
        end
      end
    RUBY
  end

  it "registers no offense for self.call" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        def self.call(x:)
          new(x: x).call
        end
        def call; end
      end
    RUBY
  end

  it "registers no offense for non-call methods on constants" do
    expect_no_offenses(<<~RUBY, file)
      class FooService
        def call
          SomeModel.find(1)
        end
      end
    RUBY
  end

  it "registers no offense outside service files" do
    expect_no_offenses(<<~RUBY, "app/jobs/foo_job.rb")
      class FooJob
        def perform
          SomeService.call(x: 1)
        end
      end
    RUBY
  end
end
