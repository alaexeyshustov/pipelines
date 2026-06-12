module Evaluation
  module Improvement
    class LoadSamplesTool < ::RubyLLM::Tool
      description "Fetch random samples from the experiment"

      param :experiment_id, type: :integer, desc: "ID of the experiment to get evaluation samples from.", required: true
      param :number_of_samples, type: :integer, desc: "Number of samples in the output", required: false

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
