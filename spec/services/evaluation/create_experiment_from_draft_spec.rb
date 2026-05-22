# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::CreateExperimentFromDraft do
  let(:dataset) { create(:evaluation_dataset) }
  let(:prompt)  { create(:orchestration_prompt) }
  let!(:metric) { create(:evaluation_metric, agent_name: prompt.name, active: true) }

  def build_draft(payload)
    create(:evaluation_wizard_draft, payload: payload, step: 4)
  end

  before { allow(Evaluation::ExperimentJob).to receive(:perform_later) }

  describe ".call" do
    context "when prompt_id is present in the payload" do
      let(:draft) do
        build_draft(
          "prompt_id"        => prompt.id.to_s,
          "experiment_name"  => "My Eval",
          "dataset_id"       => dataset.id,
          "sample_model"     => "gpt-4",
          "evaluation_model" => "gpt-4"
        )
      end

      it "creates an experiment" do
        expect { described_class.call(draft: draft) }.to change(Evaluation::Experiment, :count).by(1)
      end

      it "returns the created experiment" do
        result = described_class.call(draft: draft)
        expect(result).to be_a(Evaluation::Experiment)
      end

      it "sets the experiment name from payload" do
        result = described_class.call(draft: draft)
        expect(result.name).to eq("My Eval")
      end

      it "resolves prompt by prompt_id from payload" do
        result = described_class.call(draft: draft)
        expect(result.prompt_id.to_s).to eq(prompt.id.to_s)
      end

      it "enqueues ExperimentJob" do
        experiment = described_class.call(draft: draft)
        expect(Evaluation::ExperimentJob).to have_received(:perform_later).with(experiment)
      end

      it "destroys the draft" do
        draft_id = draft.id
        described_class.call(draft: draft)
        expect(Evaluation::WizardDraft.find_by(id: draft_id)).to be_nil
      end
    end

    context "when prompt_id is absent but agent_name is present" do
      let(:draft) do
        build_draft(
          "prompt_id"        => "",
          "agent_name"       => prompt.name,
          "experiment_name"  => "Agent Eval",
          "dataset_id"       => dataset.id,
          "sample_model"     => nil,
          "evaluation_model" => nil
        )
      end

      it "falls back to the latest prompt for agent_name" do
        result = described_class.call(draft: draft)
        expect(result.prompt_id.to_s).to eq(prompt.id.to_s)
      end

      it "creates an experiment" do
        expect { described_class.call(draft: draft) }.to change(Evaluation::Experiment, :count).by(1)
      end
    end

    context "when experiment_name is absent" do
      let(:draft) do
        build_draft(
          "prompt_id"        => prompt.id.to_s,
          "experiment_name"  => "",
          "dataset_id"       => dataset.id,
          "sample_model"     => nil,
          "evaluation_model" => nil
        )
      end

      it "defaults the name to 'Manual eval'" do
        result = described_class.call(draft: draft)
        expect(result.name).to eq("Manual eval")
      end
    end

    context "when agent has no active metrics" do
      before { metric.update!(active: false) }

      let(:draft) do
        build_draft(
          "prompt_id"        => prompt.id.to_s,
          "experiment_name"  => "No Metrics Eval",
          "dataset_id"       => dataset.id,
          "sample_model"     => nil,
          "evaluation_model" => nil
        )
      end

      it "raises Evaluation::NoMetricsError" do
        expect { described_class.call(draft: draft) }.to raise_error(Evaluation::NoMetricsError)
      end

      it "does not create an experiment" do
        expect { described_class.call(draft: draft) }.to raise_error(Evaluation::NoMetricsError)
        expect(Evaluation::Experiment.count).to eq(0)
      end

      it "does not call MetricSuggester" do
        allow(Evaluation::MetricSuggester).to receive(:call)
        expect { described_class.call(draft: draft) }.to raise_error(Evaluation::NoMetricsError)
        expect(Evaluation::MetricSuggester).not_to have_received(:call)
      end
    end

    context "when Experiment.create! raises ActiveRecord::RecordInvalid" do
      let(:draft) do
        build_draft(
          "prompt_id"        => prompt.id.to_s,
          "experiment_name"  => "Bad Eval",
          "dataset_id"       => nil,
          "sample_model"     => nil,
          "evaluation_model" => nil
        )
      end

      it "raises ActiveRecord::RecordInvalid" do
        allow(Evaluation::Experiment).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
        expect { described_class.call(draft: draft) }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
