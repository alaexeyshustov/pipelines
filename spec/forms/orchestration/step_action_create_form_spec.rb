
require "rails_helper"

RSpec.describe Orchestration::StepActionCreateForm do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step)     { create(:orchestration_step, pipeline: pipeline) }
  let(:action)   { create(:orchestration_action, name: "Classify Emails") }

  def build_form(action_id: action.id)
    described_class.new(step: step, action_id: action_id)
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

    context "when a unique-key collision occurs (race condition)" do
      let(:deriver) { Struct.new(:derive).new("classify_emails") }
      let(:step_action) { step.step_actions.build(action_id: action.id, position: 1, output_key: "classify_emails") }

      before do
        allow(Orchestration::OutputKeyDeriver).to receive(:new).and_return(deriver)
        allow(step.step_actions).to receive(:build).and_return(step_action)

        first_call = true
        allow(step_action).to receive(:save).and_wrap_original do |m, *args|
          if first_call
            first_call = false
            raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed"
          end
          m.call(*args)
        end
      end

      it "saves with a hex-suffixed key" do
        expect { build_form.save }.to change(Orchestration::StepAction, :count).by(1)
        expect(step.step_actions.last.output_key).to match(/\Aclassify_emails_[0-9a-f]+\z/)
      end
    end
  end
end
