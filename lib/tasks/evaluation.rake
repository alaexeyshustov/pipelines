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

  desc "Seed a Leva dataset from historical action runs (e.g. rake evaluation:seed_dataset[Emails::ClassifyAgent,20])"
  task :seed_dataset, [ :agent_name, :sample_size ] => :environment do |_, args|
    agent_name  = args[:agent_name]  or raise ArgumentError, "Usage: rake evaluation:seed_dataset[AgentName,sample_size]"
    sample_size = (args[:sample_size] || 20).to_i

    raise ArgumentError, "Unknown agent: #{agent_name}" unless Orchestration::Agent.exists?(name: agent_name)

    result = Evaluation::DatasetSeeder.call(agent_name: agent_name, sample_size: sample_size)
    puts "Dataset '#{result.agent_name}': #{result.created} created, #{result.skipped} skipped."
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

  desc "Migrate hardcoded agent instructions into Evaluation::Prompt records"
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

      Evaluation::Prompt.find_or_initialize_by(name: agent_class).tap do |prompt|
        prompt.system_prompt = klass.instructions
        # user_prompt is intentionally preserved on re-runs to avoid clobbering manual edits
        prompt.user_prompt = prompt.user_prompt.presence || "{{input}}"
        prompt.save!
      end
    end
    Rails.logger.info "Migrated #{agent_classes.size} agent prompts to Evaluation::Prompt."
  end

  desc "Compare two experiments and print per-metric deltas (e.g. rake evaluation:compare[1,2])"
  task :compare, [ :baseline_id, :candidate_id ] => :environment do |_, args|
    baseline_id  = args[:baseline_id]  or raise ArgumentError, "Usage: rake evaluation:compare[baseline_id,candidate_id]"
    candidate_id = args[:candidate_id] or raise ArgumentError, "Usage: rake evaluation:compare[baseline_id,candidate_id]"

    baseline  = Evaluation::Experiment.find(baseline_id)
    candidate = Evaluation::Experiment.find(candidate_id)

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

  desc "Run an evaluation for a specific agent (e.g. rake evaluation:run[Emails::ClassifyAgent,mistral-large-latest])"
  task :run, [ :agent_name, :model ] => :environment do |_, args|
    agent_name = args[:agent_name] or raise ArgumentError, "Usage: rake evaluation:run[agent_name,model]"

    prompt = Evaluation::Prompt.where(name: agent_name).order(version: :desc, id: :desc).first
    raise ArgumentError, "No active prompt found for #{agent_name}" unless prompt

    dataset = Evaluation::Dataset.find_by!(name: agent_name)

    model_label = args[:model].presence || "default"
    experiment = Evaluation::Experiment.create!(
      name: "#{agent_name} eval w/ #{model_label} (#{Date.today})",
      dataset: dataset,
      prompt: prompt,
      runner_class: "StubbedAgentRun",
      evaluator_classes: [ "LLMJudgeEval" ],
      metadata: args[:model].presence ? { "pipeline_model" => args[:model] } : nil
    )

    Evaluation::ExperimentJob.perform_later(experiment)
    puts "Created experiment ##{experiment.id} for #{agent_name}"
  end

  desc "Run evaluations for all agents (e.g. rake evaluation:run_all[mistral-large-latest])"
  task :run_all, [ :model ] => :environment do |_, args|
    model = args[:model].presence

    Orchestration::Agent.pluck(:name).each do |agent_name|
      prompt = Evaluation::Prompt.where(name: agent_name).order(version: :desc, id: :desc).first
      unless prompt
        puts "#{agent_name}: skipped (no prompt)"
        next
      end

      dataset = Evaluation::Dataset.find_by(name: agent_name)
      unless dataset
        puts "#{agent_name}: skipped (no dataset)"
        next
      end

      model_label = model || "default"
      experiment = Evaluation::Experiment.create!(
        name: "#{agent_name} eval w/ #{model_label} (#{Date.today})",
        dataset: dataset,
        prompt: prompt,
        runner_class: "StubbedAgentRun",
        evaluator_classes: [ "LLMJudgeEval" ],
        metadata: model ? { "pipeline_model" => model } : nil
      )

      Evaluation::ExperimentJob.perform_later(experiment)
      puts "#{agent_name}: created experiment ##{experiment.id}"
    end
  end

  desc "Print evaluation readiness status per agent"
  task status: :environment do
    agent_names = Orchestration::Agent.pluck(:name)

    # steep:ignore:start
    sample_counts = Orchestration::ActionRun
      .joins(step_action: { action: :agent })
      .where(status: "completed")
      .where.not(chat_id: nil)
      .group("orchestration_agents.name")
      .count
    # steep:ignore:end

    latest_exp_ids = Evaluation::Experiment
      .joins(:prompt)
      .where(evaluation_prompts: { name: agent_names })
      .group("evaluation_prompts.name")
      .maximum(:id)

    experiments_by_id = Evaluation::Experiment.where(id: latest_exp_ids.values).index_by(&:id)
    exp_by_agent      = latest_exp_ids.transform_values { |id| experiments_by_id[id] }

    avg_scores = latest_exp_ids.any? ?
      Evaluation::EvaluationResult.where(experiment_id: latest_exp_ids.values).group(:experiment_id).average(:score) :
      {}

    prompt_versions = Evaluation::Prompt
      .where(name: agent_names)
      .group(:name)
      .maximum(:version)

    puts format("%-35s %10s %10s %8s %7s", "Agent", "Samples", "Exp ID", "Score", "Prompt")
    puts "-" * 75

    agent_names.each do |agent_name|
      samples     = sample_counts[agent_name] || 0
      experiment  = exp_by_agent[agent_name]
      exp_id      = experiment ? "##{experiment.id}" : "n/a"
      avg_score   = experiment ? avg_scores[experiment.id] : nil
      score_str   = avg_score ? format("%.2f", avg_score) : "n/a"
      version     = prompt_versions[agent_name]
      version_str = version ? "v#{version}" : "n/a"

      puts format("%-35s %10s %10s %8s %7s", agent_name, samples, exp_id, score_str, version_str)
    end
  end

  desc "Improve prompt for an agent based on the latest completed experiment (e.g. rake evaluation:improve[Emails::ClassifyAgent])"
  task :improve, [ :agent_name ] => :environment do |_, args|
    agent_name = args[:agent_name] or raise ArgumentError, "Usage: rake evaluation:improve[AgentName]"

    experiment = Evaluation::Experiment
      .joins(:prompt)
      .where(evaluation_prompts: { name: agent_name })
      .where(status: :completed)
      .order(id: :desc)
      .first

    raise ArgumentError, "No completed experiment found for #{agent_name}" unless experiment

    prompt = Evaluation::PromptImprover.call(experiment: experiment)
    puts "Created improved prompt v#{prompt.version} for #{agent_name} (id: #{prompt.id})"
  end
end
