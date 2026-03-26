require "rails_helper"

RSpec.describe "async-job infrastructure" do # rubocop:disable RSpec/DescribeClass
  describe "queue adapter" do
    it "is configured as :async_job" do
      expect(Rails.application.config.active_job.queue_adapter).to eq(:async_job)
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

    it "executes a job synchronously via perform_later" do
      SmokeJob.perform_later

      expect(SmokeJob.executed).to be true
    end
  end
end
