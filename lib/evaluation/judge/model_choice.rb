module Evaluation
  module Judge
    # RubyLLM::Judge needs a model with the `judgment` capability (gpt-6-luna, jev-*). Old experiments may carry
    # a plain chat model (e.g. gpt-5.4); those cannot judge, so fall back: preferred -> LlmModels.judge ->
    # RubyLLM's default_judgment_model (jev-latest).
    # The OpenAI judge path uses the Decisions endpoint, independent of `openai_protocol = :chat_completions`.
    class ModelChoice
      def self.call(preferred)
        candidates = [ preferred, LlmModels.judge, RubyLLM.config.default_judgment_model ].filter_map(&:presence)
        candidates.find { |id| judgment_model?(id) } || candidates.last.to_s
      end

      def self.judgment_model?(id)
        model = RubyLLM.models.find(id)
        # gpt-6-luna is registered as type :chat with the `judgment` capability; jev-* have type :judgment.
        model.type == :judgment || model.capabilities.include?("judgment")
      rescue RubyLLM::ModelNotFoundError
        false
      end
      private_class_method :judgment_model?
    end
  end
end
