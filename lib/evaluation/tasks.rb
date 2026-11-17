module Evaluation
  # Bodies of the evaluation:* rake tasks (lib/tasks/evaluation.rake). They report on +out+.
  module Tasks
    module_function

    def extract_metrics(agent_name, out: $stdout)
      MetricExtractor.call(required(agent_name, "extract_metrics[AgentName]")).each do |metric|
        out.puts "name: #{metric['name']}", "description: #{metric['description']}", "---"
      end
    end

    def seed_dataset(agent_name, sample_size, out: $stdout)
      agent_name = required(agent_name, "seed_dataset[AgentName,sample_size]")
      raise ArgumentError, "Unknown agent: #{agent_name}" unless Orchestration::Agent.exists?(name: agent_name)

      result = DatasetSeeder.call(agent_name:, sample_size: (sample_size || 20).to_i)
      out.puts "Dataset '#{result.agent_name}': #{result.created} created, #{result.skipped} skipped."
    end

    def seed_metrics(agent_name, out: $stdout)
      agent_name = required(agent_name, "seed_metrics[AgentName]")
      result = MetricSeeder.call(agent_name:)
      out.puts "Seeded metrics for #{agent_name}: #{result.created} created, #{result.updated} updated."
    end

    def required(value, usage)
      value || raise(ArgumentError, "Usage: rake evaluation:#{usage}")
    end
  end
end
