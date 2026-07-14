module Orchestration
  class ActionExecutor
    include SteepHacks

    def initialize(action_run:, pipeline_run:, prompt_cache:)
      @action_run = action_run
      @pipeline_run = pipeline_run
      @prompt_cache = prompt_cache
      @output_parser = ModelOutputParser.new
    end

    def call
      @action_run.update!(status: "running", started_at: Time.current)
      action    = @action_run.step_action.action
      policy    = action.agent? ? resolve_policy : nil
      validate_input_schema!
      execution = run_agent(policy:)
      validate_agent_output!(action, execution, policy:)
      @action_run.update!(status: "completed", output: execution[:output], error: nil, error_details: nil, finished_at: Time.current)
    rescue StandardError => error
      handle_action_failure(error, raw_content: execution&.dig(:raw_content))
    end

    private

    def validate_agent_output!(action, execution, policy:)
      return unless action.agent?
      raise ArgumentError, "policy missing for agent action" unless policy

      @output_parser.validate!(execution[:output], policy:, raw_content: execution[:raw_content])
    end

    def validate_input_schema!
      schema = @action_run.step_action.action.input_schema
      return unless schema

      SchemaValidator.new(schema).validate!(@action_run.input || empty_object)
    end

    def run_agent(policy: nil)
      action = @action_run.step_action.action
      input  = @action_run.input || empty_object # : json_object

      if action.agent?
        raise ArgumentError, "policy missing for agent action" unless policy
        run_as_agent(input, policy)
      else
        run_as_service(action, input)
      end
    end

    def run_as_agent(input, policy)
      agent = RuntimeAgentBuilder.new(policy: policy).build
      @action_run.update_columns(**build_agent_columns(agent, policy))
      result = agent.ask(input.to_json)
      output = @output_parser.parse(result.content, structured_output_expected: policy.output_schema.present?)
      { output: normalize_agent_output(output, result, policy), raw_content: result.content }
    end

    def build_agent_columns(agent, policy)
      chat_id = agent.respond_to?(:chat) ? agent.chat&.id : agent.id
      {
        chat_id: chat_id,
        agent_snapshot: {
          model: policy.model,
          prompt: policy.prompt,
          tools: policy.tools&.map(&:to_s) || [],
          output_schema: policy.output_schema
        }
      }
    end

    def normalize_agent_output(output, result, policy)
      if policy.output_schema.present?
        output
      else
        { "result" => output.nil? && result.content.is_a?(String) ? result.content : output }
      end
    end

    def run_as_service(action, input)
      klass = ServiceRegistry.lookup(action.agent_class)
      raise ArgumentError, "Service class not found: #{action.agent_class}" unless klass

      { output: klass.call(**input.transform_keys(&:to_sym)), raw_content: nil }
    end

    def resolve_policy
      action = @action_run.step_action.action
      AgentResolutionPolicy.new(
        action: action,
        pipeline_model: @pipeline_run.pipeline.model,
        prompt_override: prompt_for(action.agent&.name)
      ).resolve
    end

    def handle_action_failure(error, raw_content:)
      failure = NormalizeActionRunFailure.new(error:, action_run: @action_run, raw_content:).normalize
      @action_run.update!(
        status: "failed",
        error: failure.summary,
        error_details: failure.details,
        finished_at: Time.current
      )
      log_action_failure(failure) if failure.details.present?
    end

    def log_action_failure(failure)
      details = failure.details || empty_object

      Rails.logger.error(
        {
          event: "orchestration.action_run_failed",
          category: details["category"],
          provider: details["provider"],
          model: details["model"],
          status_code: details["status_code"],
          action_run_id: @action_run.id,
          pipeline_run_id: @pipeline_run.id,
          chat_id: details["chat_id"],
          summary: failure.summary
        }.to_json
      )
    end

    def prompt_for(agent_class)
      return @prompt_cache[agent_class] if @prompt_cache.key?(agent_class)

      @prompt_cache[agent_class] = Evaluation::Prompt.last_for_agent(agent_class)&.system_prompt
    end
  end
end
