module Evaluation
  class DatasetSeeder
    Result = Data.define(:agent_name, :created, :skipped)

    def self.call(agent_name:, sample_size: 20)
      new(agent_name: agent_name, sample_size: sample_size).call
    end

    def initialize(agent_name:, sample_size: 20)
      @agent_name = agent_name
      @sample_size = sample_size
    end

    def call
      dataset
      counts = candidate_runs.each_with_object({ created: 0, skipped: 0 }) do |run, acc|
        process_run(run, acc)
      end
      Result.new(agent_name: @agent_name, created: counts[:created], skipped: counts[:skipped])
    end

    private

    def process_run(run, acc)
      sample = sample_for(run)
      if sample.new_record?
        sample.input = run.input
        sample.expected_tool_calls = ToolCallExtractor.call(run.chat)
        sample.save!
        acc[:created] += 1
      else
        acc[:skipped] += 1
      end
    end

    def dataset
      @dataset ||= Dataset.find_or_create_by!(name: @agent_name) { |d| d.agent_name = @agent_name }
    end

    def sample_for(run)
      dataset.dataset_samples.find_or_initialize_by(source_run_id: run.id)
    end

    def candidate_runs
      Orchestration::AgentRunsQuery.completed_with_chat(agent_name: @agent_name, limit: @sample_size)
    end
  end
end
