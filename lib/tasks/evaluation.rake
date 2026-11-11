namespace :evaluation do
  desc "Print candidate metrics for an agent without persisting (e.g. rake evaluation:extract_metrics[Orchestration::Agents::EmailsClassifier])"
  task :extract_metrics, [ :agent_name ] => :environment do |_, args|
    agent_name = args[:agent_name] or raise ArgumentError, "Usage: rake evaluation:extract_metrics[AgentName]"
    candidates = Evaluation::MetricExtractor.call(agent_name)
    candidates.each do |metric|
      puts "name: #{metric['name']}"
      puts "description: #{metric['description']}"
      puts "---"
    end
  end

  desc "Seed an evaluation dataset from historical action runs (e.g. rake evaluation:seed_dataset[Orchestration::Agents::EmailsClassifier,20])"
  task :seed_dataset, [ :agent_name, :sample_size ] => :environment do |_, args|
    agent_name  = args[:agent_name]  or raise ArgumentError, "Usage: rake evaluation:seed_dataset[AgentName,sample_size]"
    sample_size = (args[:sample_size] || 20).to_i

    raise ArgumentError, "Unknown agent: #{agent_name}" unless Orchestration::Agent.exists?(name: agent_name)

    result = Evaluation::DatasetSeeder.call(agent_name: agent_name, sample_size: sample_size)
    puts "Dataset '#{result.agent_name}': #{result.created} created, #{result.skipped} skipped."
  end

  desc "Persist extracted metrics for an agent (e.g. rake evaluation:seed_metrics[Orchestration::Agents::EmailsClassifier])"
  task :seed_metrics, [ :agent_name ] => :environment do |_, args|
    agent_name = args[:agent_name] or raise ArgumentError, "Usage: rake evaluation:seed_metrics[AgentName]"
    candidates = Evaluation::MetricExtractor.call(agent_name)
    created = 0
    updated = 0
    candidates.each do |metric|
      record = Evaluation::Metric.find_or_initialize_by(agent_name: agent_name, name: metric["name"])
      was_new = record.new_record?
      record.description = metric["description"]
      record.save!
      was_new ? created += 1 : updated += 1
    end
    puts "Seeded metrics for #{agent_name}: #{created} created, #{updated} updated."
  end
end
