require "rails_helper"

RSpec.describe Evaluation::PromptDiffer do
  let(:prompt) { build(:orchestration_prompt, version: 2, system_prompt: "Be concise.\nAnswer.", user_prompt: "Classify {{input}}") }

  describe "with two prompt versions" do
    let(:other) { build(:orchestration_prompt, version: 1, system_prompt: "Be verbose.\nAnswer.", user_prompt: "Classify {{input}}") }

    it "marks changed system prompt lines" do
      lines = described_class.new(other, prompt).system_prompt_diff

      expect(lines.select { |l| l.type == :removed }.map(&:text)).to eq([ "Be verbose." ])
      expect(lines.select { |l| l.type == :added }.map(&:text)).to eq([ "Be concise." ])
    end
  end

  describe "with an AgentDefaultPrompt as the baseline" do
    let(:agent_default) { Evaluation::AgentDefaultPrompt.new(system_prompt: "Be verbose.\nAnswer.", user_prompt: "") }

    it "diffs the system prompt against the agent default" do
      lines = described_class.new(agent_default, prompt).system_prompt_diff

      expect(lines.select { |l| l.type == :removed }.map(&:text)).to eq([ "Be verbose." ])
      expect(lines.select { |l| l.type == :added }.map(&:text)).to eq([ "Be concise." ])
    end

    it "treats the agent default's empty user prompt as empty text" do
      lines = described_class.new(agent_default, prompt).user_prompt_diff

      expect(lines.map(&:type).uniq).to eq([ :added ])
    end
  end
end
