FactoryBot.define do
  factory :orchestration_step_action, class: 'Orchestration::StepAction' do
    association :step, factory: :orchestration_step
    association :action, factory: :orchestration_action
    sequence(:position) { |n| n }
    sequence(:output_key) { |n| "step_action_#{n}" }
  end
end
