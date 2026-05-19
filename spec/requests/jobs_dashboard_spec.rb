# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Jobs dashboard" do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :solid_queue
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  describe "GET /jobs" do
    it "returns a successful response" do
      get "/jobs"

      expect(response).to have_http_status(:ok)
    end
  end
end
