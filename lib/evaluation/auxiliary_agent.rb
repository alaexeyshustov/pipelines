module Evaluation
  # Base for the LLM helpers around evaluation (prompt improver, metric extractor/suggester). Structured output
  # only, evaluation model, and cross-provider fallbacks (RubyLLM Chat#with_fallbacks) so a provider outage or
  # rate limit does not fail the call. The model that actually answered is on the response (`model_id`) and in
  # the ruby_llm_usages rows when run inside UsageScope.
  class AuxiliaryAgent < ::RubyLLM::Agent
    model LlmModels.evaluation
    fallbacks(*LlmModels.evaluation_fallbacks) if LlmModels.evaluation_fallbacks.any?
  end
end
