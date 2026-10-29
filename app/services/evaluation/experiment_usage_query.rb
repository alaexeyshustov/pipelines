module Evaluation
  # Tokens and cost of the LLM calls made for experiments (ruby_llm_usages rows owned by the experiment, see
  # UsageScope): sampling, judging and prompt improvement. One query per call, any number of experiments.
  #
  #   Evaluation::ExperimentUsageQuery.call(experiment_ids: [1, 2])[1].cost  # => BigDecimal
  #
  # Only succeeded attempts are summed. Cost is the sum of recorded totals; attempts whose model has no
  # pricing contribute tokens but no cost. +models+ counts attempts per model that actually answered, so a
  # fallback shows up there. Experiments without usage map to EMPTY.
  class ExperimentUsageQuery
    Usage = Data.define(:input_tokens, :output_tokens, :total_tokens, :cache_read_tokens, :cost, :calls, :models)

    EMPTY = Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0, cache_read_tokens: 0, cost: BigDecimal("0"),
                      calls: 0, models: {}).freeze

    def self.call(experiment_ids:)
      new(experiment_ids:).call
    end

    def initialize(experiment_ids:)
      @experiment_ids = Array(experiment_ids)
    end

    def call
      totals = totals_by_experiment
      models = models_by_experiment
      Hash.new(EMPTY).merge(
        totals.to_h { |id, row| [ id, build_usage(row, models.fetch(id) { {} }) ] }
      )
    end

    private

    # RubyLLM's usage model is not in our RBS; keep the untyped ActiveRecord calls in these two methods.
    def scope
      usage = RubyLLM::ActiveRecord::Usage # steep:ignore
      usage.where(owner_type: Experiment.polymorphic_name, owner_id: @experiment_ids, status: "succeeded") # steep:ignore
    end

    def totals_by_experiment
      rows = scope.group(:owner_id) # steep:ignore
                  .pluck(:owner_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(input_tokens), 0)"),
                         Arel.sql("COALESCE(SUM(output_tokens), 0)"), Arel.sql("COALESCE(SUM(cache_read_tokens), 0)"),
                         Arel.sql("COALESCE(SUM(total_cost), 0)"))
      rows.to_h { |id, *row| [ id, row ] }
    end

    def models_by_experiment
      memo = {} # : Hash[Integer, Hash[String, Integer]]
      scope.group(:owner_id, :model).count.each do |(id, model), count| # steep:ignore
        (memo[id] ||= {})[model] = count
      end
      memo
    end

    def build_usage(row, models)
      calls, input, output, cache_read, cost = row.map(&:to_s)
      Usage.new(input_tokens: input.to_i, output_tokens: output.to_i, total_tokens: input.to_i + output.to_i,
                cache_read_tokens: cache_read.to_i, cost: BigDecimal(cost.to_s), calls: calls.to_i, models: models)
    end
  end
end
