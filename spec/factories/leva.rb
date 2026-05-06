FactoryBot.define do
  factory :leva_dataset, class: "Leva::Dataset" do
    sequence(:name) { |n| "dataset_#{n}" }
  end

  factory :orchestration_prompt, class: "Orchestration::Prompt" do
    sequence(:name) { |n| "agent_#{n}" }
    system_prompt { "System prompt" }
    user_prompt { "User prompt {{input}}" }
  end

  factory :leva_experiment, class: "Leva::Experiment" do
    sequence(:name) { |n| "experiment_#{n}" }
    status { :pending }
    runner_class { "StubbedAgentRun" }
    evaluator_classes { [ "LLMJudgeEval" ] }
    association :dataset, factory: :leva_dataset
    association :prompt, factory: :orchestration_prompt
  end

  factory :leva_dataset_record, class: "Leva::DatasetRecord" do
    association :dataset, factory: :leva_dataset
    association :recordable, factory: :orchestration_action_run
  end

  factory :leva_runner_result, class: "Leva::RunnerResult" do
    prediction { { tool_calls: [], output: "classified" }.to_json }
    runner_class { "StubbedAgentRun" }
    association :experiment, factory: :leva_experiment
    association :dataset_record, factory: :leva_dataset_record
    association :prompt, factory: :orchestration_prompt
  end

  factory :leva_evaluation_result, class: "Leva::EvaluationResult" do
    evaluator_class { "LLMJudgeEval" }
    score { 4.0 }
    association :dataset_record, factory: :leva_dataset_record
    association :runner_result, factory: :leva_runner_result
  end
end
