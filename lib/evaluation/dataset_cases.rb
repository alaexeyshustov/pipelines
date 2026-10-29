module Evaluation
  # Adapts dataset samples to native RubyLLM::Evaluation cases.
  #
  # Case names are "sample-<id>": stable across runs and unique per dataset sample.
  # DatasetSample has no reference-answer column, so expected_output is never set;
  # the reference tool trace travels in metadata[:expected_tool_calls].
  module DatasetCases
    def self.call(dataset:)
      dataset.dataset_samples.order(:id).map { |sample| for_sample(sample) }
    end

    def self.for_sample(dataset_sample)
      RubyLLM::Evaluation::Case.new(
        name: "sample-#{dataset_sample.id}",
        inputs: dataset_sample.input,
        metadata: { expected_tool_calls: dataset_sample.expected_tool_calls || [] }
      )
    end
  end
end
