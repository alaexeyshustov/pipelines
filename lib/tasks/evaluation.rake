namespace :evaluation do
  desc "Print candidate metrics for an agent without persisting (e.g. rake evaluation:extract_metrics[Orchestration::Agents::EmailsClassifier])"
  task(:extract_metrics, [ :agent_name ] => :environment) { |_, args| Evaluation::Tasks.extract_metrics(args[:agent_name]) }
  desc "Seed an evaluation dataset from historical action runs (e.g. rake evaluation:seed_dataset[Orchestration::Agents::EmailsClassifier,20])"
  task(:seed_dataset, [ :agent_name, :sample_size ] => :environment) { |_, args| Evaluation::Tasks.seed_dataset(args[:agent_name], args[:sample_size]) }
  desc "Persist extracted metrics for an agent (e.g. rake evaluation:seed_metrics[Orchestration::Agents::EmailsClassifier])"
  task(:seed_metrics, [ :agent_name ] => :environment) { |_, args| Evaluation::Tasks.seed_metrics(args[:agent_name]) }
end
