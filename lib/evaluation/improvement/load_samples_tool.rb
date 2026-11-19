module Evaluation
  module Improvement
    class LoadSamplesTool < ::RubyLLM::Tool
      description "Fetch random samples from the experiment"

      parameter :experiment_id, type: :integer, description: "ID of the experiment to get evaluation samples from.", required: true
      parameter :number_of_samples, type: :integer, description: "Number of samples in the output", required: false

      MAX_SAMPLES = 20
      MAX_CHARS = 4_000
      TAG = "untrusted_sample".freeze
      TRUNCATION_MARKER = "[truncated]".freeze

      def name = "load_samples"

      def execute(experiment_id:, number_of_samples: 5)
        samples = load_samples(experiment_id, number_of_samples.clamp(1, MAX_SAMPLES))
        filter_samples(samples)
      end

      private

      def load_samples(experiment_id, number_of_samples)
        Sample
          .where(experiment_id: experiment_id)
          .includes(:dataset_sample)
          .order(Arel.sql("RANDOM()"))
          .limit(number_of_samples)
          .to_a # : Array[Evaluation::Sample]
      end

      def filter_samples(samples)
        samples.filter_map do |s|
          next unless s.dataset_sample
          { input: wrap(s.dataset_sample.input.to_json), output: wrap(s.output.to_s) }
        end
      end

      # Sample data comes from real inputs and model output, so it is delimited as data, never instructions.
      def wrap(text)
        text = "#{text[0, MAX_CHARS]}#{TRUNCATION_MARKER}" if text.length > MAX_CHARS
        "<#{TAG}>#{text.gsub("</#{TAG}>", "<\\/#{TAG}>")}</#{TAG}>"
      end
    end
  end
end
