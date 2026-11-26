module Orchestration
  # What the run dialog tells the user next to a field, from the first step's executor: an executor that defines
  # +run_hints+ (a Hash of input field => text) is asked, once. Only the first action of the first enabled step is
  # consulted, because only its input comes from the run form. Anything else gives no hints.
  class RunHints
    def self.call(pipeline)
      new(pipeline).call
    end

    def initialize(pipeline)
      @pipeline = pipeline
    end

    def call
      executor = first_executor
      executor.respond_to?(:run_hints) ? executor.run_hints : {} # steep:ignore
    end

    private

    def first_executor
      step = @pipeline.enabled_steps.includes(step_actions: :action).first
      action = step&.step_actions&.min_by { |step_action| step_action.position.to_i }&.action
      ServiceRegistry.lookup(action&.agent_class) unless action&.agent?
    end
  end
end
