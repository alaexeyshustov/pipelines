# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::InputMappingForm do
  let(:pipeline)    { create(:orchestration_pipeline) }
  let(:step)        { create(:orchestration_step, pipeline: pipeline) }
  let(:action)      { create(:orchestration_action, name: "Classify Emails") }
  let(:step_action) { create(:orchestration_step_action, step: step, action: action, output_key: "classify_emails") }

  def build_form(input_mapping: {}, new_key: nil, new_from: nil, new_path: nil)
    described_class.new(
      step_action: step_action,
      input_mapping: ActionController::Parameters.new(input_mapping),
      new_key: new_key,
      new_from: new_from,
      new_path: new_path
    )
  end

  describe "#save" do
    context "with a valid input_mapping" do
      let(:mapping) { { "email" => { "from" => "_initial", "path" => "" } } }

      it "returns true" do
        expect(build_form(input_mapping: mapping).save).to be true
      end

      it "saves the input_mapping to the step_action" do
        build_form(input_mapping: mapping).save
        expect(step_action.reload.input_mapping).to eq("email" => { "from" => "_initial", "path" => "" })
      end

      it "exposes the InputMappingUpdater result" do
        form = build_form(input_mapping: mapping)
        form.save
        expect(form.result).to respond_to(:saved)
      end
    end

    context "when appending a new mapping entry" do
      it "merges new_key/new_from into the mapping and saves" do
        build_form(new_key: "result", new_from: "_initial").save
        expect(step_action.reload.input_mapping).to have_key("result")
      end

      it "includes new_path when provided" do
        build_form(new_key: "result", new_from: "_initial", new_path: "data.0").save
        expect(step_action.reload.input_mapping["result"]).to eq("from" => "_initial", "path" => "data.0")
      end

      it "omits path from entry when new_path is absent" do
        build_form(new_key: "result", new_from: "_initial").save
        expect(step_action.reload.input_mapping["result"]).to eq("from" => "_initial")
      end
    end

    context "when new_key has an invalid format" do
      it "returns false" do
        expect(build_form(new_key: "Bad Key!", new_from: "_initial").save).to be false
      end

      it "adds an error describing the invalid key" do
        form = build_form(new_key: "Bad Key!", new_from: "_initial")
        form.save
        expect(form.errors.full_messages.first).to include("is invalid")
      end

      it "does not update the step_action" do
        original = step_action.input_mapping
        build_form(new_key: "Bad Key!", new_from: "_initial").save
        expect(step_action.reload.input_mapping).to eq(original)
      end
    end

    context "when InputMappingUpdater returns errors" do
      it "returns false" do
        expect(build_form(input_mapping: { "email" => { "from" => "nonexistent_key" } }).save).to be false
      end
    end
  end
end
