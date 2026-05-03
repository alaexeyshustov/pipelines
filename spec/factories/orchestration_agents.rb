FactoryBot.define do
  factory :orchestration_agent, class: "Orchestration::Agent" do
    sequence(:name) { |n| "Agent::Class#{n}" }
    enabled { true }
  end
end
