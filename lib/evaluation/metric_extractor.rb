module Evaluation
  class MetricExtractor
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an evaluation expert. Given an agent's instructions, identify evaluable behaviors and return candidate metrics as a JSON array.
      Each metric must have a "name" (snake_case, concise) and a "description" (rubric text explaining what to measure and how to score).
      Return ONLY the JSON array with no additional text.
    PROMPT

    DEFAULT_MODEL = LlmModels.evaluation

    def self.call(agent_name)
      new(agent_name).call
    end

    def initialize(agent_name)
      raise ArgumentError, "agent_name must not be blank" if agent_name.blank?

      @agent_name = agent_name
    end

    def call
      current_prompt = load_prompt!

      response = RubyLLM.chat(model: DEFAULT_MODEL)
                        .with_instructions(SYSTEM_PROMPT)
                        .ask("Agent instructions:\n\n#{current_prompt.system_prompt}")

      parse_metrics(response.content)
    end

    private

    def load_prompt!
      prompt = Prompt.last_for_agent(@agent_name)
      if prompt.nil?
        raise ArgumentError, "No prompt found for agent: #{@agent_name}"
      else
        prompt
      end
    end

    def parse_metrics(content)
      parsed = JSON::Helpers.parse_maybe(content)
      raise ArgumentError, "Metric extraction returned non-array for agent #{@agent_name}" unless parsed.is_a?(Array)

      validate_metric_entries!(parsed)

      parsed.filter_map do |metric|
        next unless metric.is_a?(Hash)

        { "name" => metric["name"].to_s, "description" => metric["description"].to_s }
      end
    rescue JSON::ParserError => e
      raise ArgumentError,
            "Metric extraction returned invalid JSON for agent #{@agent_name}: #{truncate(content.to_s)} (#{e.message})"
    end

    def validate_metric_entries!(entries)
      entries.each_with_index do |metric, i|
        next if metric.is_a?(Hash) &&
                metric["name"].is_a?(String) && metric["name"].present? &&
                metric["description"].is_a?(String) && metric["description"].present?

        raise ArgumentError,
              "Invalid metric at index #{i} for agent #{@agent_name}: expected Hash with string name and description"
      end
    end

    def truncate(content, limit = 200)
      str = content.to_s.gsub(/\s+/, " ").strip
      str.length > limit ? "#{str[0, limit]}..." : str
    end
  end
end
