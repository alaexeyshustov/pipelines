# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::PipelineRunForm do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:form) { described_class.new(pipeline: pipeline) }

  describe "#save" do
    context "when no active run exists" do
      before { allow(PipelineRunJob).to receive(:perform_later) }

      it "creates a pipeline run with status pending and triggered_by manual" do
        expect { form.save }.to change(Orchestration::PipelineRun, :count).by(1)
        run = Orchestration::PipelineRun.last
        expect(run.status).to eq("pending")
        expect(run.triggered_by).to eq("manual")
      end

      it "returns true" do
        expect(form.save).to be true
      end

      it "exposes the created pipeline run" do
        form.save
        expect(form.pipeline_run).to be_a(Orchestration::PipelineRun)
        expect(form.pipeline_run).to be_persisted
      end
    end

    context "when a pending run already exists" do
      before { create(:orchestration_pipeline_run, pipeline: pipeline, status: "pending") }

      it "does not create a new run" do
        expect { form.save }.not_to change(Orchestration::PipelineRun, :count)
      end

      it "returns false" do
        expect(form.save).to be false
      end

      it "adds an error message" do
        form.save
        expect(form.errors.full_messages).to include("A run is already pending.")
      end
    end

    context "when a running run already exists" do
      before { create(:orchestration_pipeline_run, pipeline: pipeline, status: "running") }

      it "does not create a new run and is invalid" do
        form.save
        expect(form.errors).not_to be_empty
      end
    end

    context "with initial_input_schema" do
      let(:schema) do
        { "type" => "object", "required" => ["date"],
          "properties" => { "date" => { "type" => "string" } } }
      end
      let(:pipeline) { create(:orchestration_pipeline, initial_input_schema: schema) }

      context "when initial_input is valid" do
        let(:raw_params) { ActionController::Parameters.new("date" => "2026-05-20") }
        let(:form) { described_class.new(pipeline: pipeline, initial_input_params: raw_params) }

        before { allow(PipelineRunJob).to receive(:perform_later) }

        it "creates the run with initial_input set" do
          form.save
          expect(Orchestration::PipelineRun.last.initial_input).to eq("date" => "2026-05-20")
        end
      end

      context "when initial_input is missing a required field" do
        let(:raw_params) { ActionController::Parameters.new({}) }
        let(:form) { described_class.new(pipeline: pipeline, initial_input_params: raw_params) }

        it "returns false" do
          expect(form.save).to be false
        end

        it "adds a schema validation error" do
          form.save
          expect(form.errors.full_messages.first).to include("missing required key")
        end
      end
    end

    context "without initial_input_schema" do
      let(:form) do
        raw = ActionController::Parameters.new("anything" => "value")
        described_class.new(pipeline: pipeline, initial_input_params: raw)
      end

      before { allow(PipelineRunJob).to receive(:perform_later) }

      it "stores nil as initial_input regardless of params" do
        form.save
        expect(Orchestration::PipelineRun.last.initial_input).to be_nil
      end
    end
  end
end
