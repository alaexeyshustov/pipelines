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
      dataset = Dataset.find_or_create_by!(name: @agent_name)
      created = 0
      skipped = 0

      candidate_runs.each do |run|
        record = dataset.dataset_records.find_or_create_by!(
          recordable_type: "Orchestration::ActionRun",
          recordable_id: run.id
        )
        if record.previously_new_record?
          created += 1
        else
          skipped += 1
        end
      end

      Result.new(agent_name: @agent_name, created: created, skipped: skipped)
    end

    private

    def candidate_runs
      # join table types not modelled in sig/shims
      # steep:ignore:start
      Orchestration::ActionRun
        .joins(step_action: { action: :agent })
        .where(status: "completed")
        .where.not(chat_id: nil)
        .where(orchestration_agents: { name: @agent_name })
        .order(id: :desc)
        .limit(@sample_size)
      # steep:ignore:end
    end
  end
end
