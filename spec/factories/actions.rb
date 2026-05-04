FactoryBot.define do
  factory :orchestration_action, class: "Orchestration::Action" do
    sequence(:name) { |n| "Action #{n}" }
    kind { :agent }
    association :agent, factory: :orchestration_agent, strategy: :create

    trait :service_kind do
      kind { :service }
      agent { nil }
      agent_class { nil }
    end
  end
end
