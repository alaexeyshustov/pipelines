# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Solid Queue infrastructure" do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper
  describe "queue adapter" do
    it "uses the :test adapter in the test environment" do
      expect(Rails.application.config.active_job.queue_adapter).to eq(:test)
    end
  end

  describe "job execution" do
    before do
      stub_const("SmokeJob", Class.new(ApplicationJob) do
        cattr_accessor :executed, default: false

        def perform
          self.class.executed = true
        end
      end)
    end

    after { SmokeJob.executed = false }

    it "does not execute a job immediately when perform_later is called" do
      SmokeJob.perform_later

      expect(SmokeJob.executed).to be false
    end

    it "executes the job when drained via perform_enqueued_jobs" do
      perform_enqueued_jobs { SmokeJob.perform_later }

      expect(SmokeJob.executed).to be true
    end
  end
end
