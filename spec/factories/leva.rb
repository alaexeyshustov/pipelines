FactoryBot.define do
  factory :leva_dataset, class: "Evaluation::Dataset" do
    sequence(:name) { |n| "dataset_#{n}" }
  end

  factory :orchestration_prompt, class: "Evaluation::Prompt" do
    sequence(:name) { |n| "agent_#{n}" }
    system_prompt { "System prompt" }
    user_prompt { "User prompt {{input}}" }
  end

  factory :leva_experiment, class: "Evaluation::Experiment" do
    sequence(:name) { |n| "experiment_#{n}" }
    status { :pending }
    runner_class { "Evaluation::Runners::StubbedAgentRun" }
    evaluator_classes { [ "Evaluation::Evaluators::LLMJudgeEval" ] }
    association :dataset, factory: :leva_dataset
    association :prompt, factory: :orchestration_prompt
  end

  factory :leva_dataset_record, class: "Evaluation::DatasetRecord" do
    association :dataset, factory: :leva_dataset
    association :recordable, factory: :orchestration_action_run
  end

  factory :leva_runner_result, class: "Evaluation::RunnerResult" do
    prediction { { tool_calls: [], output: "classified" }.to_json }
    runner_class { "Evaluation::Runners::StubbedAgentRun" }
    association :experiment, factory: :leva_experiment
    association :dataset_record, factory: :leva_dataset_record
    association :prompt, factory: :orchestration_prompt
  end

  factory :leva_evaluation_result, class: "Evaluation::EvaluationResult" do
    evaluator_class { "Evaluation::Evaluators::LLMJudgeEval" }
    score { 4.0 }
    association :dataset_record, factory: :leva_dataset_record
    association :runner_result, factory: :leva_runner_result
  end
end
