require "rails_helper"
require_relative "emails_classifier_evaluation"

RSpec.describe Evaluation::Regression::EmailsClassifierEvaluation do # rubocop:disable RSpec/SpecFilePathFormat
  describe "golden dataset" do
    it "loads native cases without calling the API" do
      cases = described_class.cases

      expect(cases).to all(be_a(RubyLLM::Evaluation::Case))
      expect(cases.map(&:name).uniq.size).to eq(cases.size)
    end

    it "builds the agent without tools" do
      expect(described_class.build_agent.tools).to be_empty
    end
  end

  # Live regression gate: needs real credentials, so it is skipped unless EVALS=1 (see docs/evals.md).
  describe "regression gate", :eval, vcr: { cassette_name: "evals/emails_classifier" } do # rubocop:disable RSpec/EmptyExampleGroup
    extend RubyLLM::Evaluation::RSpec

    evaluates described_class
  end
end
