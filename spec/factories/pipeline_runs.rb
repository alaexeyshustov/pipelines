FactoryBot.define do
  factory :orchestration_pipeline_run, class: 'Orchestration::PipelineRun' do
    association :pipeline, factory: :orchestration_pipeline
    status { 'pending' }
    triggered_by { 'manual' }
  end
end
