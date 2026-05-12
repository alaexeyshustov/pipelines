FactoryBot.define do
  factory :evaluation_synthetic_record, class: "Evaluation::SyntheticRecord" do
    agent_name { "Emails::ClassifyAgent" }
    input { { "email" => "subject: Job offer" } }
  end
end
