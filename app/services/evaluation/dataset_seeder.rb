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
      runs = candidate_runs
      dataset = Leva::Dataset.find_or_create_by!(name: @agent_name)
      existing_ids = dataset.dataset_records
                            .where(recordable_type: "Orchestration::ActionRun")
                            .pluck(:recordable_id).to_set

      created = 0
      skipped = 0

      runs.each do |run|
        if existing_ids.include?(run.id)
          skipped += 1
        else
          dataset.dataset_records.create!(recordable: run)
          created += 1
        end
      end

      Result.new(agent_name: @agent_name, created: created, skipped: skipped)
    end

    private

    def candidate_runs
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
