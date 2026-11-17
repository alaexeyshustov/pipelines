module Evaluation
  # Persists the metrics MetricExtractor proposes for an agent, updating the descriptions of existing ones by name.
  class MetricSeeder
    Result = Data.define(:created, :updated)

    def self.call(agent_name:)
      new(agent_name:).call
    end

    def initialize(agent_name:)
      @agent_name = agent_name
    end

    def call
      metrics = MetricExtractor.call(@agent_name)
      existing = existing_by_name(metrics.pluck("name"))
      metrics.each { |metric| seed(existing[metric["name"]], metric) }
      updated = metrics.count { |metric| existing.key?(metric["name"]) }
      Result.new(created: metrics.size - updated, updated:)
    end

    private

    def existing_by_name(names)
      Metric.where(agent_name: @agent_name, name: names).index_by(&:name)
    end

    def seed(record, metric)
      record ||= Metric.new(agent_name: @agent_name, name: metric["name"])
      record.update!(description: metric["description"])
    end
  end
end
