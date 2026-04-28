FactoryBot.define do
  factory :evaluation_metric, class: "Evaluation::Metric" do
    agent_name { "Emails::ClassifyAgent" }
    sequence(:name) { |n| "metric_#{n}" }
    description { "Measures the quality of the agent output" }
    weight { 1.0 }
    active { true }
  end
end
