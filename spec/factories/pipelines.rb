FactoryBot.define do
  factory :orchestration_pipeline, class: 'Orchestration::Pipeline' do
    sequence(:name) { |n| "Pipeline #{n}" }
    enabled { true }
  end
end
