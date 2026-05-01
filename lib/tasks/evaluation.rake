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

  desc "Compare two experiments and print per-metric deltas (e.g. rake evaluation:compare[1,2])"
  task :compare, [ :baseline_id, :candidate_id ] => :environment do |_, args|
    baseline_id  = args[:baseline_id]  or raise ArgumentError, "Usage: rake evaluation:compare[baseline_id,candidate_id]"
    candidate_id = args[:candidate_id] or raise ArgumentError, "Usage: rake evaluation:compare[baseline_id,candidate_id]"

    baseline  = Leva::Experiment.find(baseline_id)
    candidate = Leva::Experiment.find(candidate_id)

    result = Evaluation::Comparison.call(baseline_experiment: baseline, candidate_experiment: candidate)

    puts "Experiment comparison"
    puts "  Baseline:  ##{baseline.id} — #{baseline.name}"
    puts "  Candidate: ##{candidate.id} — #{candidate.name}"
    puts ""
    puts format("%-30s %8s %8s %10s", "Metric", "Baseline", "Candidate", "Delta")
    puts "-" * 60

    result.metric_deltas.each do |metric_name, delta|
      b_avg     = result.baseline_metrics[metric_name]
      c_avg     = result.candidate_metrics[metric_name]
      b_str     = b_avg ? format("%.2f", b_avg) : "n/a"
      c_str     = c_avg ? format("%.2f", c_avg) : "n/a"
      delta_str = delta  ? format("%+.2f", delta) : "n/a"

      puts format("%-30s %8s %8s %10s", metric_name, b_str, c_str, delta_str)
    end

    puts "-" * 60
    baseline_str  = result.baseline_score  ? format("%.2f", result.baseline_score)  : "n/a"
    candidate_str = result.candidate_score ? format("%.2f", result.candidate_score) : "n/a"
    delta_str     = result.overall_delta   ? format("%+.2f", result.overall_delta)  : "n/a"
    puts format("%-30s %8s %8s %10s", "OVERALL", baseline_str, candidate_str, delta_str)
  end
end
