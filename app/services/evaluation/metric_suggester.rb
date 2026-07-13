# frozen_string_literal: true

module Evaluation
  class MetricSuggester
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an evaluation designer. Given an AI agent's system prompt, suggest 3 to 7
      evaluation metrics that measure the quality of its outputs.
      Return ONLY a JSON array with no additional text. Each element must have:
      - "name": short metric name (string)
      - "description": rubric description (string)
      - "weight": relative importance, float between 0.0 and 1.0
    PROMPT

    DEFAULT_MODEL = LlmModels.evaluation

    class Error < StandardError; end

    def self.call(agent_name:, model: nil)
      new(agent_name: agent_name, model:).call
    end

    def initialize(agent_name:, model: DEFAULT_MODEL)
      @agent_name = agent_name
      @model = model
    end

    def call
      prompt_to_analyze = agent_system_prompt
      raise Error, "No prompt found for agent '#{@agent_name}'" if prompt_to_analyze.blank?

      parse_response(query_llm(prompt_to_analyze).content)
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "MetricSuggester failed: #{e.message}"
    end

    private

    def query_llm(prompt)
      RubyLLM.chat(model: @model)
              .with_temperature(0)
              .with_instructions(SYSTEM_PROMPT)
              .ask(prompt)
    end

    def agent_system_prompt
      Prompt.last_for_agent(@agent_name)&.system_prompt
    end

    def parse_response(content)
      parsed = JSON::Helpers.parse_maybe(content)
      raise Error, "Expected JSON array" unless parsed.is_a?(Array)

      parsed.filter_map { |entry| parse_metric_entry(entry) }
    end

    def parse_metric_entry(entry)
      return unless entry.is_a?(Hash)

      name, description, weight = extract_metric_fields(entry)
      return if name.blank? || description.blank?
      return if out_of_range_weight?(weight)

      { name: name, description: description, weight: weight }
    rescue ArgumentError, TypeError
      Rails.logger.warn("MetricSuggester: dropping unparseable entry #{entry.inspect}")
      nil
    end

    def extract_metric_fields(entry)
      [
        entry["name"].to_s.strip,
        entry["description"].to_s.strip,
        Float(entry["weight"]) #: Float
      ]
    end

    def out_of_range_weight?(weight)
      return false if weight.between?(0.0, 1.0)

      Rails.logger.warn("MetricSuggester: dropping entry with out-of-range weight #{weight}")
      true
    end
  end
end
