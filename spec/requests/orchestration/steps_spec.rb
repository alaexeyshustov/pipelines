# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orchestration::Steps" do
  let(:pipeline) { create(:orchestration_pipeline) }

  describe "PATCH /orchestration/pipelines/:pipeline_id/steps/:id/toggle" do
    context "when the step is enabled" do
      let(:step) { create(:orchestration_step, pipeline: pipeline, enabled: true) }

      it "disables the step and redirects to the pipeline" do
        patch toggle_orchestration_pipeline_step_path(pipeline, step)

        expect(step.reload.enabled).to be(false)
        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      end
    end

    context "when the step is disabled" do
      let(:step) { create(:orchestration_step, pipeline: pipeline, enabled: false) }

      it "enables the step and redirects to the pipeline" do
        patch toggle_orchestration_pipeline_step_path(pipeline, step)

        expect(step.reload.enabled).to be(true)
        expect(response).to redirect_to(orchestration_pipeline_path(pipeline))
      end
    end
  end
end
