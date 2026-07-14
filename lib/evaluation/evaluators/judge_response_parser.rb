module Evaluation
  module Evaluators
    class JudgeResponseParser
      def self.parse_output(output)
        new.parse_output(output)
      end

      def self.parse(content)
        new.parse(content)
      end

      def parse_output(output)
        return "" if output.blank?

        JSON.parse(output)
      rescue JSON::ParserError, TypeError
        output
      end

      def parse(content)
        entries = coerce_to_array(content)
        raise ArgumentError, "expected Array" unless entries.is_a?(Array)

        entries.each_with_index.filter_map { |entry, i| normalize_entry(entry, i) }
      rescue JSON::ParserError, ArgumentError => e
        Rails.logger.error("JudgeResponseParser: failed to parse judge response: #{e.message}")
        []
      end

      private

      def coerce_to_array(content)
        if content.is_a?(Hash)
          Array(content["evaluations"])
        elsif content.is_a?(Array)
          content
        else
          str_content = content #: String
          JSON.parse(str_content)
        end
      end

      def normalize_entry(entry, index)
        return nil unless entry.is_a?(Hash)

        raw_score = entry["score"]
        return nil if raw_score.nil?

        score, metric_name, justification = extract_score_fields(entry, raw_score)
        return log_invalid_entry(index) unless valid_score_entry?(score, metric_name, justification)

        { metric_name: metric_name, score: score, justification: justification }
      rescue ArgumentError, TypeError
        Rails.logger.warn("JudgeResponseParser: dropping entry #{index}: unparseable score #{raw_score.inspect}")
        nil
      end

      def extract_score_fields(entry, raw_score)
        [ Float(raw_score), entry["metric_name"].to_s.strip, entry["justification"].to_s.strip ] #: [Float, String, String]
      end

      def valid_score_entry?(score, metric_name, justification)
        score.between?(1.0, 5.0) && metric_name.present? && justification.present?
      end

      def log_invalid_entry(index)
        Rails.logger.warn("JudgeResponseParser: dropping entry #{index}: score out of range or missing fields")
        nil
      end
    end
  end
end
