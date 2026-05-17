module Evaluation
  class MetricExtractor
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an evaluation expert. Given an agent's instructions, identify evaluable behaviors and return candidate metrics as a JSON array.
      Each metric must have a "name" (snake_case, concise) and a "description" (rubric text explaining what to measure and how to score).
      Return ONLY the JSON array with no additional text.
    PROMPT

    DEFAULT_MODEL = ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")

    def self.call(agent_name)
      new(agent_name).call
    end

    def initialize(agent_name)
      raise ArgumentError, "agent_name must not be blank" if agent_name.blank?

      @agent_name = agent_name
    end

    def call
      prompt = Evaluation::Prompt.where(name: @agent_name).order(version: :desc, id: :desc).first
      raise ArgumentError, "No prompt found for agent: #{@agent_name}" if prompt.nil?

      response = RubyLLM.chat(model: DEFAULT_MODEL)
                        .with_instructions(SYSTEM_PROMPT)
                        .ask("Agent instructions:\n\n#{prompt.system_prompt}")

      parse_metrics(response.content)
    end

    private

    def parse_metrics(content)
      parsed = JSON.parse(content)
      validate_metrics!(parsed)
      parsed
    rescue JSON::ParserError => e
      raise ArgumentError,
            "Metric extraction returned invalid JSON for agent #{@agent_name}: #{truncate(content)} (#{e.message})"
    end

    def validate_metrics!(metrics)
      unless metrics.is_a?(Array)
        raise ArgumentError,
              "Metric extraction returned non-array for agent #{@agent_name}"
      end

      metrics.each_with_index do |metric, i|
        unless metric.is_a?(Hash) &&
               metric["name"].is_a?(String) && metric["name"].present? &&
               metric["description"].is_a?(String) && metric["description"].present?
          raise ArgumentError,
                "Invalid metric at index #{i} for agent #{@agent_name}: expected Hash with string name and description"
        end
      end
    end

    def truncate(content, limit = 200)
      str = content.to_s.gsub(/\s+/, " ").strip
      str.length > limit ? "#{str[0, limit]}..." : str
    end
  end
end
