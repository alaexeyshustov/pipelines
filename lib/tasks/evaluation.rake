namespace :evaluation do
  desc "Print candidate metrics for an agent without persisting (e.g. rake evaluation:extract_metrics[Emails::ClassifyAgent])"
  task :extract_metrics, [ :agent_name ] => :environment do |_, args|
    agent_name = args[:agent_name] or raise ArgumentError, "Usage: rake evaluation:extract_metrics[AgentName]"
    candidates = Evaluation::MetricExtractor.call(agent_name)
    candidates.each do |metric|
      puts "name: #{metric['name']}"
      puts "description: #{metric['description']}"
      puts "---"
    end
  end

  desc "Persist extracted metrics for an agent (e.g. rake evaluation:seed_metrics[Emails::ClassifyAgent])"
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

  desc "Migrate hardcoded agent instructions into Leva::Prompt records"
  task migrate_prompts: :environment do
    agent_classes = %w[
      Emails::ClassifyAgent
      Emails::FilterAgent
      Emails::MappingAgent
      Records::FillAgent
      Records::NormalizeAgent
      Records::StoreAgent
      Records::ReconcileAgent
    ].freeze

    agent_classes.each do |agent_class|
      klass = agent_class.constantize
      raise "#{agent_class} has no instructions" if klass.instructions.blank?

      Leva::Prompt.find_or_initialize_by(name: agent_class).tap do |prompt|
        prompt.system_prompt = klass.instructions
        # user_prompt is intentionally preserved on re-runs to avoid clobbering manual edits
        prompt.user_prompt = prompt.user_prompt.presence || "{{input}}"
        prompt.save!
      end
    end
    Rails.logger.info "Migrated #{agent_classes.size} agent prompts to Leva::Prompt."
  end
end
