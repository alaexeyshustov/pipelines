require "rails_helper"

RSpec.describe Evaluation::Judge::Questions do
  it "builds one question per metric keyed by name with the native type" do
    metrics = [
      build(:evaluation_metric, name: "p", description: "Is it right?"),
      build(:evaluation_metric, :score, name: "s", description: "How right?"),
      build(:evaluation_metric, :choice, name: "c", description: "Which bucket?")
    ]
    questions = described_class.call(metrics)

    expect(questions["p"]).to eq(type: :probability, instructions: "Is it right?")
    expect(questions["s"]).to eq(type: :score, instructions: "How right?", levels: [ "Wrong", "Partly right", "Fully right" ])
    expect(questions["c"]).to eq(type: :choice, instructions: "Which bucket?",
                                 options: { "good" => "Fully correct", "ok" => "Acceptable", "bad" => "Incorrect" })
  end

  it "passes yes/no criteria for probability metrics when defined" do
    metric = build(:evaluation_metric, name: "p", levels: { "yes" => "Right", "no" => "Wrong" })
    expect(described_class.call([ metric ]).fetch("p")).to include(criteria: { "yes" => "Right", "no" => "Wrong" })
  end

  it "is accepted by the native RubyLLM judge question validation" do
    metrics = [ build(:evaluation_metric, :score, name: "s"), build(:evaluation_metric, :choice, name: "c") ]
    questions = described_class.call(metrics)
    expect { questions.each { |name, definition| RubyLLM::Judge::Question.from_h(name, definition).resolve(nil) } }
      .not_to raise_error
  end
end
