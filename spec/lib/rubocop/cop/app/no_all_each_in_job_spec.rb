
require "support/rubocop_support"
require "rubocop/cop/app_cops"

RSpec.describe RuboCop::Cop::App::NoAllEachInJob, :config do
  let(:file) { "app/jobs/report_job.rb" }

  it "registers an offense for .all.each" do
    expect_offense(<<~RUBY, file)
      class ReportJob < ApplicationJob
        def perform
          User.all.each { |u| process(u) }
          ^^^^^^^^^^^^^ Do not use `.all.each` in jobs; use `find_each` for memory-safe batch iteration.
        end
      end
    RUBY
  end

  it "registers no offense for find_each" do
    expect_no_offenses(<<~RUBY, file)
      class ReportJob < ApplicationJob
        def perform
          User.find_each { |u| process(u) }
        end
      end
    RUBY
  end

  it "registers no offense outside job files" do
    expect_no_offenses(<<~RUBY, "app/services/foo_service.rb")
      class FooService
        def call
          User.all.each { |u| process(u) }
        end
      end
    RUBY
  end
end
