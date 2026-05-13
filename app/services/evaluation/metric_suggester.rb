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

    DEFAULT_MODEL = ENV.fetch("EVALUATION_LLM_MODEL", "gpt-5.4")

    class Error < StandardError; end

    def self.call(agent_name:, model: nil)
      new(agent_name: agent_name, model:).call
    end

    def initialize(agent_name:, model: DEFAULT_MODEL)
      @agent_name = agent_name
      @model = model
    end

    def call
      prompt_to_analyze = orchestration_prompt
      raise Error, "No prompt found for agent '#{@agent_name}'" if prompt_to_analyze.blank?

      # steep:ignore:start
      response = RubyLLM.chat(model: @model)
                        .with_temperature(0)
                        .with_instructions(SYSTEM_PROMPT)
                        .ask(prompt_to_analyze)
      # steep:ignore:end

      parse_response(response.content)
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "MetricSuggester failed: #{e.message}"
    end

    private

    def orchestration_prompt
      Orchestration::Prompt
        .where(name: @agent_name)
        .order(version: :desc, id: :desc)
        .first
        &.system_prompt
    end

    def parse_response(content)
      parsed = JSON.parse(content)
      raise Error, "Expected JSON array" unless parsed.is_a?(Array)

      parsed.filter_map do |entry|
        name        = entry["name"].to_s.strip
        description = entry["description"].to_s.strip
        weight      = Float(entry["weight"])

        next if name.blank? || description.blank?
        unless weight.between?(0.0, 1.0)
          Rails.logger.warn("MetricSuggester: dropping entry with out-of-range weight #{weight}")
          next
        end

        { name: name, description: description, weight: weight }
      rescue ArgumentError, TypeError
        Rails.logger.warn("MetricSuggester: dropping unparseable entry #{entry.inspect}")
        nil
      end
    end
  end
end
