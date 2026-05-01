# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::PromptDiffComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:prompt_class) { Data.define(:name, :version, :system_prompt, :user_prompt) }

  let(:prompt_a) do
    prompt_class.new(
      name: "classify",
      version: 1,
      system_prompt: "You are an assistant.\nBe helpful.",
      user_prompt: "Classify the email."
    )
  end

  let(:prompt_b) do
    prompt_class.new(
      name: "classify",
      version: 2,
      system_prompt: "You are an expert assistant.\nBe concise.",
      user_prompt: "Classify the email."
    )
  end

  let(:component) { described_class.new(prompt_a: prompt_a, prompt_b: prompt_b) }

  it "renders a diff container" do
    expect(rendered.css("[data-diff]")).to be_present
  end

  it "renders removed lines with red highlight" do
    removed = rendered.css(".bg-red-100")
    expect(removed.map(&:text).join).to include("You are an assistant.")
  end

  it "renders added lines with green highlight" do
    added = rendered.css(".bg-green-100")
    expect(added.map(&:text).join).to include("You are an expert assistant.")
  end

  it "renders unchanged lines without color highlight" do
    unchanged_text = rendered.css("[data-diff] span:not(.bg-red-100):not(.bg-green-100)")
    expect(unchanged_text.map(&:text).join).to include("Be")
  end

  it "shows version labels for both prompts" do
    expect(rendered.text).to include("v1")
    expect(rendered.text).to include("v2")
  end

  context "with identical prompts" do
    let(:component) { described_class.new(prompt_a: prompt_a, prompt_b: prompt_a) }

    it "renders no added or removed lines" do
      expect(rendered.css(".bg-red-100")).to be_empty
      expect(rendered.css(".bg-green-100")).to be_empty
    end
  end
end
