require 'rails_helper'

RSpec.describe PipelineRunJob do
  it 'delegates to Orchestration::PipelineRunner' do
    pipeline_run = create(:orchestration_pipeline_run)
    runner = instance_double(Orchestration::PipelineRunner, call: nil)
    allow(Orchestration::PipelineRunner).to receive(:new).with(pipeline_run).and_return(runner)

    described_class.perform_now(pipeline_run.id)

    expect(runner).to have_received(:call)
  end
end
