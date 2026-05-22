FactoryBot.define do
  factory :evaluation_dataset, class: "Evaluation::Dataset" do
    sequence(:name) { |n| "dataset_#{n}" }
  end

  factory :orchestration_prompt, class: "Evaluation::Prompt" do
    sequence(:name) { |n| "agent_#{n}" }
    system_prompt { "System prompt" }
    user_prompt { "User prompt {{input}}" }
  end

  factory :evaluation_experiment, class: "Evaluation::Experiment" do
    sequence(:name) { |n| "experiment_#{n}" }
    status { :pending }
    evaluator_classes { [ "Evaluation::Evaluators::LLMJudgeEval" ] }
    association :dataset, factory: :evaluation_dataset
    association :prompt, factory: :orchestration_prompt
  end

  factory :evaluation_dataset_sample, class: "Evaluation::DatasetSample" do
    association :dataset, factory: :evaluation_dataset
    input { { "email" => "subject: Job offer" } }
    expected_tool_calls { nil }
  end

  factory :evaluation_sample, class: "Evaluation::Sample" do
    tool_calls { [] }
    output { "classified" }
    association :experiment, factory: :evaluation_experiment
    association :prompt, factory: :orchestration_prompt

    after(:build) do |sample|
      if sample.experiment && sample.dataset_sample.nil?
        sample.dataset_sample = build(:evaluation_dataset_sample, dataset: sample.experiment.dataset)
      end
    end

    after(:create) do |sample|
      if sample.experiment && sample.dataset_sample.nil?
        sample.dataset_sample = create(:evaluation_dataset_sample, dataset: sample.experiment.dataset)
      end
    end
  end

  factory :evaluation_evaluation_result, class: "Evaluation::EvaluationResult" do
    evaluator_class { "Evaluation::Evaluators::LLMJudgeEval" }
    score { 4.0 }
    association :dataset_sample, factory: :evaluation_dataset_sample
    association :sample, factory: :evaluation_sample
  end
end
