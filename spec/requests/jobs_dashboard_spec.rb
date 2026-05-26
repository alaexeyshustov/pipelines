# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Jobs dashboard" do
  describe "GET /jobs" do
    it "returns a successful response" do
      get "/jobs"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<section class="section">')
      expect(response.body).to include('<div class="container">')
    end
  end
end
