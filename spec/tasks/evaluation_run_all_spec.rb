# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "evaluation:run_all rake task" do # rubocop:disable RSpec/DescribeClass
  include RakeTaskHelpers

  let(:task_name) { "evaluation:run_all" }

  let(:classify_agent_name) { "Emails::ClassifyAgent" }
  let(:filter_agent_name)   { "Emails::FilterAgent" }

  before do
    load_rake_task(task_name)
    allow(Evaluation::ExperimentJob).to receive(:perform_later)

    create(:orchestration_agent, name: classify_agent_name)
    create(:orchestration_agent, name: filter_agent_name)
    create(:orchestration_prompt, name: classify_agent_name)
    create(:orchestration_prompt, name: filter_agent_name)
    create(:evaluation_dataset, name: classify_agent_name)
    create(:evaluation_dataset, name: filter_agent_name)
  end

  def run_task(model = nil)
    output = StringIO.new
    $stdout = output
    Rake::Task[task_name].invoke(model)
    output.string
  ensure
    $stdout = STDOUT
  end

  it "creates one experiment per agent" do
    expect { run_task }.to change(Evaluation::Experiment, :count).by(2)
  end

  it "prints a summary line for each agent" do
    output = run_task
    expect(output).to include(classify_agent_name)
    expect(output).to include(filter_agent_name)
  end

  context "when model is provided" do
    it "stores the model in each experiment metadata" do
      run_task("mistral-large-latest")
      expect(Evaluation::Experiment.all.map { |e| e.metadata&.dig("pipeline_model") }.uniq)
        .to eq([ "mistral-large-latest" ])
    end

    it "includes the model in each experiment name" do
      run_task("mistral-large-latest")
      expect(Evaluation::Experiment.all.map(&:name)).to all(include("mistral-large-latest"))
    end
  end

  context "when an agent has no prompt" do
    before { Evaluation::Prompt.where(name: classify_agent_name).delete_all }

    it "skips that agent with a message" do
      output = run_task
      expect(output).to match(/#{Regexp.escape(classify_agent_name)}.*skipped/i)
    end

    it "still creates an experiment for the other agent" do
      expect { run_task }.to change(Evaluation::Experiment, :count).by(1)
    end
  end

  context "when an agent has no dataset" do
    before { Evaluation::Dataset.where(name: classify_agent_name).delete_all }

    it "skips that agent with a message" do
      output = run_task
      expect(output).to match(/#{Regexp.escape(classify_agent_name)}.*skipped/i)
    end

    it "still creates an experiment for the other agent" do
      expect { run_task }.to change(Evaluation::Experiment, :count).by(1)
    end
  end
end
