module Orchestration
  class InputMappingResolver
    def initialize(input_mapping:, previous_outputs:)
      @input_mapping = input_mapping
      @previous_outputs = previous_outputs
    end

    def resolve
      return concatenate_all if @input_mapping.nil?

      resolve_explicit
    end

    private

    def concatenate_all
      # steep:ignore:start
      @previous_outputs.reduce({}) { |acc, entry| acc.merge(entry["output"] || {}) } # Ruby::UnannotatedEmptyCollection
      # steep:ignore:end
    end

    def resolve_explicit
      @input_mapping.transform_values do |spec|
        next spec["value"] if spec.key?("value")

        step_name = spec["from_step"]
        path      = spec["path"]
        merge     = spec["merge"]

        values = @previous_outputs
          .select { |e| e["step_name"] == step_name }
          .filter_map { |e| e.dig("output", *path.split(".")) }

        apply_merge(values, merge)
      end
    end

    def apply_merge(values, strategy)
      return values.last if strategy != "concat"

      values.join("\n")
    end
  end
end
