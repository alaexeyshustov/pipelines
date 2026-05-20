# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orchestration::StepActionCreateForm do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step)     { create(:orchestration_step, pipeline: pipeline) }
  let(:action)   { create(:orchestration_action, name: "Classify Emails") }

  def build_form(action_id: action.id, params_json: nil)
    described_class.new(step: step, action_id: action_id, params_json: params_json)
  end

  describe "#save" do
    context "with a valid action" do
      it "returns true" do
        expect(build_form.save).to be true
      end

      it "creates a step_action" do
        expect { build_form.save }.to change(Orchestration::StepAction, :count).by(1)
      end

      it "derives output_key from the action name" do
        build_form.save
        expect(step.step_actions.last.output_key).to eq("classify_emails")
      end

      it "assigns the correct position" do
        build_form.save
        expect(step.step_actions.last.position).to eq(1)
      end

      it "increments position when step already has actions" do
        create(:orchestration_step_action, step: step, action: action, position: 1, output_key: "first")
        build_form.save
        expect(step.step_actions.last.position).to eq(2)
      end

      it "exposes the created step_action" do
        form = build_form
        form.save
        expect(form.step_action).to be_a(Orchestration::StepAction)
        expect(form.step_action).to be_persisted
      end
    end

    context "with valid JSON params" do
      it "parses and stores them" do
        build_form(params_json: '{"threshold": 0.8}').save
        expect(step.step_actions.last.params).to eq("threshold" => 0.8)
      end
    end

    context "with an invalid action_id" do
      it "returns false" do
        expect(build_form(action_id: 0).save).to be false
      end

      it "does not create a step_action" do
        expect { build_form(action_id: 0).save }.not_to change(Orchestration::StepAction, :count)
      end

      it "adds an error message" do
        form = build_form(action_id: 0)
        form.save
        expect(form.errors.full_messages).to include("Invalid action.")
      end
    end

    context "with invalid JSON in params" do
      it "returns false" do
        expect(build_form(params_json: "{not json}").save).to be false
      end

      it "does not create a step_action" do
        expect { build_form(params_json: "{not json}").save }.not_to change(Orchestration::StepAction, :count)
      end

      it "adds an error message about valid JSON" do
        form = build_form(params_json: "{not json}")
        form.save
        expect(form.errors.full_messages.first).to include("valid JSON")
      end
    end

    context "when a unique-key collision occurs (race condition)" do
      before do
        allow(Orchestration::OutputKeyDeriver).to receive(:call).and_return("classify_emails")

        first_call = true
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Orchestration::StepAction).to receive(:save).and_wrap_original do |m, **opts|
          if first_call
            first_call = false
            raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed"
          end
          m.call(**opts)
        end
        # rubocop:enable RSpec/AnyInstance
      end

      it "saves with a hex-suffixed key" do
        expect { build_form.save }.to change(Orchestration::StepAction, :count).by(1)
        expect(step.step_actions.last.output_key).to match(/\Aclassify_emails_[0-9a-f]+\z/)
      end
    end
  end
end
