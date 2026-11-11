module Evaluation
  # Grades one sample with the native RubyLLM::Judge: one question per active Metric of the experiment's agent,
  # a single judgment call, one Grade per metric (scores normalized to 0.0..1.0, see GradeNormalizer).
  #
  # Decisions:
  # - Justification: Judge#score / #probability / #choice return distributions, no free-text reason (OpenAI
  #   Decisions payload has none). We do NOT run a second reviewer pass; the justification is derived
  #   deterministically from the native answer (see #justification) and includes the description of the closest
  #   level / chosen option, which is what the PromptImprover needs to see.
  # - passed: Metric#minimum (0.0..1.0) is compared with the normalized score for every kind
  #   (native Result#decision compares raw Score#score; ours is the unified scale).
  # - tokens/cost belong to the one judgment call; they are attached to the first grade only.
  # - Errors from the provider (RubyLLM::Error) propagate so the job can retry; a blank sample yields [].
  class Grader
    def self.call(experiment:, dataset_sample:, sample:)
      new(experiment:, dataset_sample:, sample:).call
    end

    def initialize(experiment:, dataset_sample:, sample:)
      @experiment = experiment
      @dataset_sample = dataset_sample
      @sample = sample
    end

    def call
      metrics = active_metrics
      return [] if metrics.empty?
      return blank_sample if @sample.tool_calls.blank? && @sample.output.blank?

      judgment = judge(metrics)
      grades = metrics.map { |metric| grade_for(metric, judgment.fetch(metric.name.to_s)) }
      attach_usage(grades, judgment)
    end

    private

    def active_metrics
      agent_name = @experiment.agent_name
      return [] unless agent_name

      Metric.active_for_agent(agent_name).order(:id).to_a
    end

    def blank_sample
      Rails.logger.error("Grader: both tool_calls and output are blank (sample #{@sample.id})")
      []
    end

    def judge(metrics)
      RubyLLM::Judge.new.judge(
        Judge::Input.call(sample: @sample, dataset_sample: @dataset_sample),
        questions: Judge::Questions.call(metrics),
        model: Judge::ModelChoice.call(@experiment.evaluation_model),
        owner: @experiment,
        metadata: { experiment_id: @experiment.id, sample_id: @sample.id }
      )
    end

    def grade_for(metric, answer)
      score = GradeNormalizer.call(value: answer, metric: metric)
      minimum = metric.minimum
      Grade.new(
        metric_name: metric.name.to_s, score: score, raw: answer.to_h, confidence: confidence(answer),
        passed: (score >= minimum if score && minimum), justification: justification(metric, answer, score),
        tokens: nil, cost: nil
      )
    end

    def confidence(answer)
      answer.confidence unless answer.is_a?(RubyLLM::Probability)
    end

    def attach_usage(grades, judgment)
      head = grades.first
      return grades unless head

      [ head.with(tokens: judgment.tokens.to_h, cost: judgment.cost.total), *grades.drop(1) ]
    end

    def justification(metric, answer, score)
      "#{metric.name}: #{percent(score)} - #{detail(metric, answer)}"
    end

    def detail(metric, answer)
      case answer
      when RubyLLM::Score then score_detail(answer)
      when RubyLLM::Choice then choice_detail(answer, metric)
      else "judged #{percent(answer.probability)} likely true: #{metric.description}"
      end
    end

    def percent(fraction) = "#{(fraction.to_f * 100).round}%"

    def distribution(probabilities)
      probabilities.map { |name, probability| "#{name}=#{percent(probability)}" }.join(", ")
    end

    def score_detail(answer)
      top = answer.levels.size - 1
      index = answer.score.round.clamp(0, top)
      "level #{index} of 0..#{top} (#{answer.score.round(2)}): #{answer.levels[index]} #{evidence(answer)}"
    end

    def choice_detail(answer, metric)
      options = metric.levels
      definition = options.is_a?(Hash) ? options[answer.choice.to_s] : nil
      description = definition["description"] if definition.is_a?(Hash)
      "chose #{answer.choice}#{" (#{description})" if description} #{evidence(answer)}"
    end

    def evidence(answer)
      "[confidence #{answer.confidence&.round(2)}; #{distribution(answer.probabilities)}]"
    end
  end
end
