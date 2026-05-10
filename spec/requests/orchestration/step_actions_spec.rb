# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::StepActions" do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step)     { create(:orchestration_step, pipeline: pipeline) }
  let(:action)   { create(:orchestration_action, name: "Classify Emails") }

  describe "POST /orchestration/pipelines/:pipeline_id/steps/:step_id/step_actions" do
    def create_path
      orchestration_pipeline_step_step_actions_path(pipeline, step)
    end

    def post_create(action_id: action.id, params_json: nil)
      post create_path, params: {
        orchestration_step_action: { action_id: action_id, params: params_json }.compact
      }
    end

    context "with a valid action" do
      it "attaches the action and redirects with notice" do
        post_create

        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
        follow_redirect!
        expect(response.body).to include("Action attached.")
      end

      it "derives output_key from the action name" do
        post_create
        expect(step.step_actions.last.output_key).to eq("classify_emails")
      end

      it "parses valid JSON params and stores them" do
        post_create(params_json: '{"threshold": 0.8}')
        expect(step.step_actions.last.params).to eq("threshold" => 0.8)
      end
    end

    context "with an invalid action_id" do
      it "redirects with an alert and does not create a step_action" do
        expect {
          post_create(action_id: 0)
        }.not_to change(Orchestration::StepAction, :count)

        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
        follow_redirect!
        expect(response.body).to include("Invalid action")
      end
    end

    context "with invalid JSON in params" do
      it "redirects with an alert and does not create a step_action" do
        expect {
          post_create(params_json: "{not json}")
        }.not_to change(Orchestration::StepAction, :count)

        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
        follow_redirect!
        expect(response.body).to include("valid JSON")
      end
    end

    context "when a unique-key collision occurs (race condition)" do
      before do
        allow(Orchestration::OutputKeyDeriver).to receive(:call).and_return("classify_emails")

        # AR uniqueness validation passes before the INSERT; the collision arrives from a
        # concurrent commit that can only be simulated by stubbing save on the instance.
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

      it "saves with a hex-suffixed key instead of raising" do
        expect { post_create }.to change(Orchestration::StepAction, :count).by(1)
        expect(step.step_actions.last.output_key).to match(/\Aclassify_emails_[0-9a-f]+\z/)
      end
    end
  end
end
