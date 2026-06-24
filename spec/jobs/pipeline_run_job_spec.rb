require 'rails_helper'

RSpec.describe PipelineRunJob do
  it 'delegates to Orchestration::PipelineRunner' do
    pipeline_run = create(:orchestration_pipeline_run)

    described_class.perform_now(pipeline_run.id)

    expect(pipeline_run.reload.status).to eq("completed")
  end
end
