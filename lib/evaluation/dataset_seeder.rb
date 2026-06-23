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
      created = 0
      skipped = 0

      candidate_runs.each do |run|
        sample = sample_for(run)
        if sample.new_record?
          sample.input = run.input
          sample.expected_tool_calls = ToolCallExtractor.call(run.chat)
          sample.save!
          created += 1
        else
          skipped += 1
        end
      end

      Result.new(agent_name: @agent_name, created: created, skipped: skipped)
    end

    private

    def dataset
      @dataset ||= Dataset.find_or_create_by!(name: @agent_name) { |d| d.agent_name = @agent_name }
    end

    def sample_for(run)
      dataset.dataset_samples.find_or_initialize_by(source_run_id: run.id)
    end

    def candidate_runs
      Orchestration::ActionRun
        .joins(step_action: { action: :agent })
        .where(status: "completed") # : Orchestration::ActionRun::relation
        .where.not(chat_id: nil) # : Orchestration::ActionRun::relation
        .where(orchestration_agents: { name: @agent_name })
        .order(id: :desc)
        .limit(@sample_size).to_a
    end
  end
end
