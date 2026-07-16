
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoSleepInSystemSpecs, :config do
  it "registers an offense for sleep in a system spec" do
    expect_offense(<<~RUBY, "spec/system/foo_spec.rb")
      it "waits" do
        sleep(1)
        ^^^^^^^^ Do not use `sleep` in system specs; use Capybara's async helpers instead.
      end
    RUBY
  end

  it "registers no offense for sleep in a non-system spec" do
    expect_no_offenses(<<~RUBY, "spec/services/foo_spec.rb")
      it "waits" do
        sleep(1)
      end
    RUBY
  end

  it "registers no offense for sleep in application code" do
    expect_no_offenses(<<~RUBY, "app/jobs/poller_job.rb")
      def perform
        sleep(5)
      end
    RUBY
  end
end
