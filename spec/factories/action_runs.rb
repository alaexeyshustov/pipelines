FactoryBot.define do
  factory :orchestration_action_run, class: 'Orchestration::ActionRun' do
    association :pipeline_run, factory: :orchestration_pipeline_run
    association :step_action, factory: :orchestration_step_action
    status { 'pending' }
  end
end
