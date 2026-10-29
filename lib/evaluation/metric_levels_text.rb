module Evaluation
  # Text form of Metric#levels for the metric editor and for round-tripping AI suggestions through a form field.
  #   score:  one level description per line, worst first.
  #   choice: one option per line, "option | value (0.0..1.0) | description".
  #   probability: no levels (nil).
  module MetricLevelsText
    SEPARATOR = "|".freeze

    def self.parse(kind:, text:)
      lines = text.to_s.lines.map(&:strip).compact_blank
      case kind.to_s
      when "score" then lines
      when "choice" then lines.to_h { |line| parse_option(line) }
      end
    end

    def self.dump(kind:, levels:)
      case kind.to_s
      when "score" then Array(levels).join("\n")
      when "choice" then levels.is_a?(Hash) ? levels.map { |name, option| dump_option(name, option) }.join("\n") : ""
      else ""
      end
    end

    def self.parse_option(line)
      name, value, description = line.split(SEPARATOR, 3).map(&:strip)
      [ name.to_s, { "description" => description.to_s, "value" => Float(value.to_s, exception: false) } ]
    end

    def self.dump_option(name, option)
      fields = option.is_a?(Hash) ? option : {} # : Hash[String, json_object_value]
      [ name, fields["value"], fields["description"] ].join(" #{SEPARATOR} ")
    end
    private_class_method :parse_option, :dump_option
  end
end
