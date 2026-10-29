module Evaluation
  class MetricExtractor
    def self.call(agent_name)
      new(agent_name).call
    end

    def initialize(agent_name)
      raise ArgumentError, "agent_name must not be blank" if agent_name.blank?

      @agent_name = agent_name
    end

    def call
      current_prompt = load_prompt!

      response = MetricExtractionAgent.new.ask("Agent instructions:\n\n#{current_prompt.system_prompt}")
      metrics_from(response)
    end

    private

    def load_prompt!
      prompt = Prompt.last_for_agent(@agent_name)
      raise ArgumentError, "No prompt found for agent: #{@agent_name}" if prompt.nil?

      prompt
    end

    def metrics_from(response)
      entries = StructuredOutput.from(response)["metrics"]
      raise ArgumentError, "Metric extraction returned no metrics for agent #{@agent_name}" unless entries.is_a?(Array)

      entries.filter_map { |entry| clean(entry) if entry.is_a?(Hash) }
    rescue JSON::ParserError => e
      raise ArgumentError, "Metric extraction returned invalid output for agent #{@agent_name}: #{e.message}"
    end

    def clean(entry)
      name = entry["name"].to_s.strip
      description = entry["description"].to_s.strip
      { "name" => name, "description" => description } if name.present? && description.present?
    end
  end
end
