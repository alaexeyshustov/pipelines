# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Models" do
  describe "GET /models" do
    let(:modalities) { instance_double(RubyLLM::Model::Modalities, input: [ "text" ], output: [ "text" ]) }
    let(:model) do
      instance_double(
        RubyLLM::Model::Info,
        id: "gpt-4o", name: "gpt-4o", display_name: "GPT-4o",
        provider: "openai", context_window: 128_000,
        input_price_per_million: 5.0, output_price_per_million: 15.0,
        modalities: modalities
      )
    end

    before { allow(RubyLLM.models).to receive(:all).and_return([ model ]) }

    it "returns 200 and lists models" do
      get models_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("GPT-4o")
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
