FactoryBot.define do
  factory :evaluation_metric, class: "Evaluation::Metric" do
    agent_name { "Emails::ClassifyAgent" }
    sequence(:name) { |n| "metric_#{n}" }
    description { "Measures the quality of the agent output" }
    weight { 1.0 }
    active { true }
    kind { "probability" }

    trait :score do
      kind { "score" }
      levels { [ "Wrong", "Partly right", "Fully right" ] }
    end

    trait :choice do
      kind { "choice" }
      levels do
        { "good" => { "description" => "Fully correct", "value" => 1.0 },
          "ok" => { "description" => "Acceptable", "value" => 0.5 },
          "bad" => { "description" => "Incorrect", "value" => 0.0 } }
      end
    end
  end
end
