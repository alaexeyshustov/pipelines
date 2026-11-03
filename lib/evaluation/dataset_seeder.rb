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
      runs = candidate_runs
      seeded = seeded_run_ids(runs)
      counts = runs.each_with_object({ created: 0, skipped: 0 }) do |run, acc|
        process_run(run, seeded, acc)
      end
      Result.new(agent_name: @agent_name, created: counts[:created], skipped: counts[:skipped])
    end

    private

    def process_run(run, seeded, acc)
      if seeded.include?(run.id)
        acc[:skipped] += 1
      else
        DatasetSample.create!(
          dataset: dataset, source_run_id: run.id, input: run.input, expected_tool_calls: ToolCallExtractor.call(run.chat)
        )
        acc[:created] += 1
      end
    end

    def dataset
      @dataset ||= Dataset.find_or_create_by!(name: @agent_name) { |d| d.agent_name = @agent_name }
    end

    def seeded_run_ids(runs)
      dataset.dataset_samples.where(source_run_id: runs.map(&:id)).pluck(:source_run_id).to_set
    end

    def candidate_runs
      Orchestration::AgentRunsQuery.completed_with_chat(agent_name: @agent_name, limit: @sample_size)
    end
  end
end
