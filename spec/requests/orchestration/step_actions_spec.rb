
require "rails_helper"

RSpec.describe "Orchestration::StepActions" do
  let(:pipeline) { create(:orchestration_pipeline) }
  let(:step)     { create(:orchestration_step, pipeline: pipeline) }
  let(:action)   { create(:orchestration_action, name: "Classify Emails") }

  describe "POST /orchestration/pipelines/:pipeline_id/steps/:step_id/step_actions" do
    let(:create_path) { orchestration_pipeline_step_step_actions_path(pipeline, step) }

    def post_create(action_id: action.id)
      post create_path, params: {
        orchestration_step_action: { action_id: action_id }
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

    context "when a unique-key collision occurs (race condition)" do
      let(:key_deriver) { Orchestration::OutputKeyDeriver.new(action_name: action.name, step: step) }

      before do
        allow(Orchestration::OutputKeyDeriver).to receive(:new).and_return(key_deriver)
        allow(key_deriver).to receive(:derive).and_return("classify_emails")

        first_call = true
        allow(Orchestration::StepAction).to receive(:new).and_wrap_original do |m, *args, **kwargs|
          instance = m.call(*args, **kwargs)
          allow(instance).to receive(:save).and_wrap_original do |m2, *save_args|
            if first_call
              first_call = false
              raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed"
            end
            m2.call(*save_args)
          end
          instance
        end
      end

      it "saves with a hex-suffixed key instead of raising" do
        expect { post_create }.to change(Orchestration::StepAction, :count).by(1)
        expect(step.step_actions.last.output_key).to match(/\Aclassify_emails_[0-9a-f]+\z/)
      end
    end
  end

  describe "PATCH /orchestration/pipelines/:pipeline_id/steps/:step_id/step_actions/:id" do
    let(:step_action) { create(:orchestration_step_action, step: step, action: action) }
    let(:update_path) { orchestration_pipeline_step_step_action_path(pipeline, step, step_action) }

    def patch_update(input_mapping: {}, new_key: nil, new_from: nil, new_path: nil)
      params = { orchestration_step_action: { input_mapping: input_mapping } }
      params[:orchestration_step_action][:new_key]  = new_key  if new_key
      params[:orchestration_step_action][:new_from] = new_from if new_from
      params[:orchestration_step_action][:new_path] = new_path if new_path
      patch update_path, params: params
    end

    context "with a valid input_mapping (no validator errors)" do
      it "saves the input_mapping and redirects with notice" do
        patch_update(input_mapping: { "email" => { "from" => "_initial", "path" => "" } })

        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
        follow_redirect!
        expect(response.body).to include("Mapping saved")
        expect(step_action.reload.input_mapping).to eq("email" => { "from" => "_initial" })
      end

      it "appends a new mapping entry when new_key and new_from are provided" do
        patch_update(new_key: "result", new_from: "_initial")

        expect(step_action.reload.input_mapping).to have_key("result")
      end
    end

    context "when PipelineValidator returns errors" do
      let(:bad_from) { "nonexistent_key" }

      it "does not save the input_mapping and redirects with alert" do
        original_mapping = step_action.input_mapping

        patch_update(input_mapping: { "email" => { "from" => bad_from, "path" => "" } })

        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
        follow_redirect!
        expect(response.body).to include("unknown output key")
        expect(step_action.reload.input_mapping).to eq(original_mapping)
      end
    end
  end
end
