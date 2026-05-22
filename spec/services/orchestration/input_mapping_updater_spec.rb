# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::InputMappingUpdater do
  let(:pipeline)    { create(:orchestration_pipeline) }
  let(:step)        { create(:orchestration_step, pipeline: pipeline) }
  let(:action)      { create(:orchestration_action, name: "Classify Emails") }
  let(:step_action) { create(:orchestration_step_action, step: step, action: action, output_key: "classify_emails") }

  describe ".call" do
    context "with a valid mapping (no validator errors)" do
      it "returns a saved result" do
        result = described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "_initial" } }
        )

        expect(result.saved).to be true
      end

      it "persists the mapping to the database" do
        described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "_initial" } }
        )

        expect(step_action.reload.input_mapping).to eq("email" => { "from" => "_initial" })
      end

      it "returns empty errors" do
        result = described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "_initial" } }
        )

        expect(result.errors).to be_empty
      end
    end

    context "when the mapping triggers validator errors (unknown from key)" do
      it "returns a not-saved result" do
        result = described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "nonexistent_key" } }
        )

        expect(result.saved).to be false
      end

      it "populates errors on the result" do
        result = described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "nonexistent_key" } }
        )

        expect(result.errors).not_to be_empty
        expect(result.errors.first.code).to eq(:unknown_from)
      end

      it "does not persist the mapping (rolls back)" do
        original_mapping = step_action.input_mapping

        described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "nonexistent_key" } }
        )

        expect(step_action.reload.input_mapping).to eq(original_mapping)
      end
    end

    context "when the mapping triggers a validator warning (param collision)" do
      before do
        action.update!(params: { "email" => "default@example.com" })
        step_action.update!(params: { "email" => "override@example.com" })
      end

      it "returns a saved result" do
        result = described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "_initial" } }
        )

        expect(result.saved).to be true
      end

      it "populates warnings on the result" do
        result = described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "_initial" } }
        )

        expect(result.warnings).not_to be_empty
        expect(result.warnings.first.code).to eq(:param_collision)
      end

      it "persists the mapping to the database" do
        described_class.call(
          step_action: step_action,
          input_mapping: { "email" => { "from" => "_initial" } }
        )

        expect(step_action.reload.input_mapping).to have_key("email")
      end
    end

    context "when the input_mapping is empty" do
      it "saves and returns empty errors and warnings" do
        result = described_class.call(step_action: step_action, input_mapping: {})

        expect(result.saved).to be true
        expect(result.errors).to be_empty
        expect(result.warnings).to be_empty
      end
    end

    context "when the step_action does not appear in the validator results" do
      it "treats missing step_result as no errors and no warnings" do
        allow(Orchestration::Pipeline::Validator).to receive(:call).and_return([])

        result = described_class.call(
          step_action: step_action,
          input_mapping: {}
        )

        expect(result.errors).to be_empty
        expect(result.warnings).to be_empty
      end
    end
  end
end
