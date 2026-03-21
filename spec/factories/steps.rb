FactoryBot.define do
  factory :orchestration_step, class: 'Orchestration::Step' do
    association :pipeline, factory: :orchestration_pipeline
    sequence(:name) { |n| "Step #{n}" }
    sequence(:position) { |n| n }
  end
end
