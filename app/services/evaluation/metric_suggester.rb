module Evaluation
  # Suggests Metric attributes for an agent. Output is schema-constrained (MetricSuggestionAgent); this class
  # only maps it to Metric columns: kind, levels (score: Array, choice: {option => {description, value}},
  # probability: nil), weight, minimum.
  class MetricSuggester
    class Error < StandardError; end

    def self.call(agent_name:, model: nil)
      new(agent_name: agent_name, model:).call
    end

    def initialize(agent_name:, model: nil)
      @agent_name = agent_name
      @model = model
    end

    def call
      prompt_to_analyze = agent_system_prompt
      raise Error, "No prompt found for agent '#{@agent_name}'" if prompt_to_analyze.blank?

      entries = StructuredOutput.from(query_llm(prompt_to_analyze))["metrics"]
      raise Error, "Expected a metrics array" unless entries.is_a?(Array)

      entries.filter_map { |entry| build_metric(entry) if entry.is_a?(Hash) }
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "MetricSuggester failed: #{e.message}"
    end

    private

    def query_llm(prompt)
      agent = MetricSuggestionAgent.new
      model = @model
      agent.with_model(model) if model
      agent.ask(prompt)
    end

    def agent_system_prompt
      Prompt.last_for_agent(@agent_name)&.system_prompt
    end

    def build_metric(entry)
      name = text(entry, "name")
      description = text(entry, "description")
      weight = Float(entry["weight"]) #: Float
      return if name.blank? || description.blank?
      return drop("out-of-range weight #{weight}") unless weight.between?(0.0, 1.0)

      kind, levels = kind_and_levels(entry)
      { name:, description:, weight:, kind:, levels:, minimum: minimum_for(entry) }
    rescue ArgumentError, TypeError
      drop("unparseable entry #{entry.inspect}")
    end

    def text(entry, key) = entry[key].to_s.strip

    # A score/choice without usable levels degrades to a probability question instead of failing the batch.
    def kind_and_levels(entry)
      case entry["kind"]
      when "score" then score_levels(entry) || [ "probability", nil ]
      when "choice" then choice_levels(entry) || [ "probability", nil ]
      else [ "probability", nil ]
      end
    end

    def score_levels(entry)
      levels = Array(entry["levels"]).map { |level| level.to_s.strip }.compact_blank
      [ "score", levels ] if levels.size >= 2
    end

    def choice_levels(entry)
      options = Array(entry["options"]).filter_map { |option| choice_option(option) if option.is_a?(Hash) }
      [ "choice", options.to_h ] if options.size >= 2
    end

    def choice_option(option)
      name = option["name"].to_s.strip
      value = Float(option["value"]) #: Float
      return if name.blank? || !value.between?(0.0, 1.0)

      [ name, { "description" => option["description"].to_s.strip, "value" => value } ]
    rescue ArgumentError, TypeError
      nil
    end

    def minimum_for(entry)
      minimum = Float(entry["minimum"]) #: Float
      minimum.clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      nil
    end

    def drop(reason)
      Rails.logger.warn("MetricSuggester: dropping entry with #{reason}")
      nil
    end
  end
end
