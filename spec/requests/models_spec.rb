# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Models" do
  describe "GET /models" do
    it "returns 200 and lists models" do
      get models_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /models/sync" do
    it "redirects to /models" do
      allow(RubyLLM::Models.instance).to receive(:refresh!)
      post sync_models_path
      expect(response).to redirect_to(models_path)
    end

    it "sets a flash notice" do
      allow(RubyLLM::Models.instance).to receive(:refresh!)
      post sync_models_path
      follow_redirect!
      expect(response.body).to include("Models synced successfully")
    end
  end
end
