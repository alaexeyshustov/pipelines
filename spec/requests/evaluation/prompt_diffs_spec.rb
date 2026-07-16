
require "rails_helper"

RSpec.describe "Evaluation::PromptDiffs" do
  describe "GET /evaluation/prompts/:id/diff" do
    let!(:prompt) { create(:orchestration_prompt, name: "Emails::ClassifyAgent", system_prompt: "v1 instructions") }

    it "returns 200" do
      get evaluation_prompt_diff_path(prompt)
      expect(response).to have_http_status(:ok)
    end

    it "renders the prompt name in the header" do
      get evaluation_prompt_diff_path(prompt)
      expect(response.body).to include(prompt.name)
    end

    context "when another version of the same prompt exists" do
      before { create(:orchestration_prompt, name: prompt.name, system_prompt: "v2 instructions") }

      it "renders both versions" do
        get evaluation_prompt_diff_path(prompt)
        expect(response.body).to include("v1 instructions")
      end
    end
  end
end
