FactoryBot.define do
  factory :orchestration_action, class: 'Orchestration::Action' do
    sequence(:name) { |n| "Action #{n}" }
    agent_class { 'Emails::ClassifyAgent' }
  end
end
