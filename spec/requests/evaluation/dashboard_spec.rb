# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evaluation::Dashboard" do
  describe "GET /evaluation" do
    it "returns 200" do
      get evaluation_root_path
      expect(response).to have_http_status(:ok)
    end

    it "shows agent names from experiments" do
      prompt = create(:orchestration_prompt, name: "EmailClassifierAgent")
      create(:evaluation_experiment, prompt: prompt, status: :completed)
      get evaluation_root_path
      expect(response.body).to include("EmailClassifierAgent")
    end
  end
end
