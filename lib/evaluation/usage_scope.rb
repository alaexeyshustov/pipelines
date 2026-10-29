module Evaluation
  # Attributes every RubyLLM call made inside the block to +experiment+ (ruby_llm_usages.owner), so cost and
  # tokens can be summed per experiment (see ExperimentUsageQuery).
  #
  # Verified from the gem source (RubyLLM::Accounting::Usage):
  # - the owner lives in Fiber storage, so it is per job thread and needs no cleanup between SolidQueue jobs;
  #   set it inside #perform, not at enqueue time;
  # - acts_as_chat records (Chat) persist usage via Usage.attributes_for(entry), and every entry captures
  #   Accounting::Usage.owner when it is built, so chat rows get owner_type/owner_id too;
  # - RubyLLM::Judge#judge(owner:) wins over the scope; nested scopes restore the outer owner;
  # - only ActiveRecord owners are stored (a nil owner just yields).
  class UsageScope
    def self.call(experiment, &)
      RubyLLM.with_usage_owner(experiment, &)
    end
  end
end
