FactoryBot.define do
  factory :orchestration_step_action, class: 'Orchestration::StepAction' do
    association :step, factory: :orchestration_step
    association :action, factory: :orchestration_action
    sequence(:position) { |n| n }
  end
end
