module Evaluation
  module Improvement
    class LoadSamplesTool < ::RubyLLM::Tool
      description "Fetch random samples from the experiment"

      parameter :experiment_id, type: :integer, description: "ID of the experiment to get evaluation samples from.", required: true
      parameter :number_of_samples, type: :integer, description: "Number of samples in the output", required: false

      def name = "load_samples"

      def execute(experiment_id:, number_of_samples: 5)
        samples = load_samples(experiment_id, number_of_samples)
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
          { input: s.dataset_sample.input, output: s.output || "" }
        end
      end
    end
  end
end
