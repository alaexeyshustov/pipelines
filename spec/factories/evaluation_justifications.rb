FactoryBot.define do
  factory :evaluation_justification, class: "Evaluation::Justification" do
    association :evaluation_result, factory: :evaluation_evaluation_result
    metric_name { "tool_call_accuracy" }
    justification { "The agent called the correct tools in the right order." }
  end
end
