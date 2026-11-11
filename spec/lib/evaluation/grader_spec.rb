require "rails_helper"

RSpec.describe Evaluation::Grader do
  subject(:grades) { described_class.call(experiment: experiment, dataset_sample: dataset_sample, sample: sample) }

  let(:experiment) { create(:evaluation_experiment, evaluation_model: "gpt-6-luna") }
  let(:dataset_sample) { create(:evaluation_dataset_sample, dataset: experiment.dataset) }
  let(:sample) { create(:evaluation_sample, experiment: experiment, dataset_sample: dataset_sample, output: "done") }
  let(:agent_name) { experiment.agent_name }
  let!(:accuracy) do
    create(:evaluation_metric, agent_name: agent_name, name: "accuracy", description: "Is it accurate?", minimum: 0.5)
  end
  let!(:quality) do
    create(:evaluation_metric, :score, agent_name: agent_name, name: "quality", description: "How good?", weight: 2.0)
  end
  let(:answers) do
    [
      { "probability" => 0.9 },
      { "score" => 1.2, "confidence" => 0.8,
        "probabilities" => [ { "label" => "0", "probability" => 0.1 }, { "label" => "1", "probability" => 0.5 },
                             { "label" => "2", "probability" => 0.4 } ] }
    ]
  end
  let!(:request) do
    stub_request(:post, "https://api.openai.com/v1/decisions").to_return do |_request|
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { model: "gpt-6-luna", answers: answers, usage: { input_tokens: 100, output_tokens: 20 } }.to_json }
    end
  end

  it "returns one normalized Grade per active metric" do
    expect(grades.map(&:metric_name)).to eq(%w[accuracy quality])
    expect(grades.map(&:score)).to eq([ 0.9, 0.6 ])
  end

  it "sends one typed question per metric with the sample payload" do
    grades
    expect(request.with { |req|
      body = JSON.parse(req.body)
      body["model"] == "gpt-6-luna" &&
        body["questions"].map { |q| [ q["name"], q["type"] ] } == [ %w[accuracy predicate], %w[quality score] ] &&
        body["input"].include?("actual_tool_calls")
    }).to have_been_requested
  end

  it "keeps the native answer, confidence and pass/fail against Metric#minimum" do
    accuracy_grade, quality_grade = grades
    expect(accuracy_grade).to have_attributes(raw: include(type: :probability, probability: 0.9), confidence: nil, passed: true)
    expect(quality_grade).to have_attributes(raw: include(type: :score, score: 1.2), confidence: 0.8, passed: nil)
  end

  it "marks a grade failed when below the minimum" do
    answers[0] = { "probability" => 0.2 }
    expect(grades.first.passed).to be(false)
  end

  it "derives a non-blank justification from the native answer" do
    expect(grades.map(&:justification)).to all(be_present)
    expect(grades.last.justification).to include("quality: 60%", "Partly right", "confidence 0.8")
  end

  it "carries the judgment's tokens and cost on the first grade only" do
    first, second = grades
    expect(first.tokens).to include(input_tokens: 100, output_tokens: 20)
    expect(second).to have_attributes(tokens: nil, cost: nil)
  end

  it "attributes usage to the experiment" do
    expect { grades }.to change {
      ActiveRecord::Base.connection.select_value(
        "SELECT COUNT(*) FROM ruby_llm_usages WHERE owner_type = 'Evaluation::Experiment' AND owner_id = #{experiment.id}"
      )
    }.by(1)
  end

  it "judges a choice metric via expected option values" do
    accuracy.update!(active: false)
    quality.update!(active: false)
    create(:evaluation_metric, :choice, agent_name: agent_name, name: "bucket")
    answers.replace([ { "choice" => "good", "confidence" => 1.0,
                        "probabilities" => [ { "value" => "good", "probability" => 0.5 },
                                             { "value" => "ok", "probability" => 0.5 },
                                             { "value" => "bad", "probability" => 0.0 } ] } ])
    expect(grades.map(&:score)).to eq([ 0.75 ])
  end

  it "returns no grades without active metrics and makes no request" do
    Evaluation::Metric.update_all(active: false)
    expect(grades).to eq([])
    expect(request).not_to have_been_requested
  end

  it "returns no grades for a blank sample" do
    sample.update!(output: nil, tool_calls: nil)
    expect(grades).to eq([])
    expect(request).not_to have_been_requested
  end

  it "lets provider errors propagate for the job to retry" do
    stub_request(:post, "https://api.openai.com/v1/decisions").to_return(status: 500, body: "{}")
    expect { grades }.to raise_error(RubyLLM::Error)
  end
end
