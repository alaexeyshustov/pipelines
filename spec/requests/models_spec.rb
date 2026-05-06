# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Models" do
  let(:modalities) { instance_double(RubyLLM::Model::Modalities, input: [ "text" ], output: [ "text" ]) }

  def build_model(id:, name:, display_name:, provider:)
    instance_double(
      RubyLLM::Model::Info,
      id: id, name: name, display_name: display_name,
      provider: provider, context_window: 128_000,
      input_price_per_million: 5.0, output_price_per_million: 15.0,
      modalities: modalities
    )
  end

  describe "GET /models" do
    let(:model) { build_model(id: "gpt-4o", name: "gpt-4o", display_name: "GPT-4o", provider: "openai") }

    before { allow(RubyLLM.models).to receive(:all).and_return([ model ]) }

    it "returns 200 and lists models" do
      get models_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("GPT-4o")
    end

    context "when searching" do
      let(:anthropic_model) { build_model(id: "claude-3", name: "claude-3", display_name: "Claude 3", provider: "anthropic") }

      before { allow(RubyLLM.models).to receive(:all).and_return([ model, anthropic_model ]) }

      it "shows matching models and hides others" do
        get models_path, params: { q: "gpt" }
        expect(response.body).to include("GPT-4o")
        expect(response.body).not_to include("Claude 3")
      end

      it "matches by provider" do
        get models_path, params: { q: "anthropic" }
        expect(response.body).to include("Claude 3")
        expect(response.body).not_to include("GPT-4o")
      end

      it "shows all models when query is blank" do
        get models_path
        expect(response.body).to include("GPT-4o")
        expect(response.body).to include("Claude 3")
      end
    end

    context "when paginating" do
      let(:many_models) do
        (1..21).map do |i|
          build_model(
            id: "model-#{format('%02d', i)}",
            name: "model-#{format('%02d', i)}",
            display_name: "Model #{format('%02d', i)}",
            provider: "openai"
          )
        end
      end

      before { allow(RubyLLM.models).to receive(:all).and_return(many_models) }

      it "shows first page by default" do
        get models_path
        expect(response.body).to include("Model 01")
        expect(response.body).not_to include("Model 21")
      end

      it "shows second page when requested" do
        get models_path, params: { page: 2 }
        expect(response.body).to include("Model 21")
        expect(response.body).not_to include("Model 01")
      end
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
