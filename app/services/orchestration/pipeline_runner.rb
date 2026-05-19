module Orchestration
  class PipelineRunner
    def initialize(pipeline_run)
      @pipeline_run = pipeline_run
    end

    def call
      @pipeline_run.update!(status: "running", started_at: Time.current)

      previous_outputs = {} # : Hash[String, Hash[String, untyped]]
      previous_outputs["_initial"] = @pipeline_run.initial_input unless @pipeline_run.initial_input.nil?

      @pipeline_run.pipeline.steps.where(enabled: true).order(:position).each do |step|
        action_runs = run_step(step, previous_outputs)

        failed_run = action_runs.find { |ar| ar.status == "failed" }
        if failed_run
          @pipeline_run.update!(status: "failed", error: failed_run.error, finished_at: Time.current)
          return
        end

        action_runs.each do |ar|
          previous_outputs[ar.step_action.output_key] = ar.output || {}
        end
      end

      @pipeline_run.update!(status: "completed", finished_at: Time.current)
    end

    private

    def run_step(step, previous_outputs)
      action_runs = step.step_actions.map do |step_action|
        empty_input = {} # : Hash[String, untyped]
        action_run = @pipeline_run.action_runs.create!(step_action: step_action, status: "pending", input: empty_input)

        begin
          resolved = InputMappingResolver.new(
            input_mapping: step_action.input_mapping || {},
            previous_outputs: previous_outputs
          ).resolve
          action_run.update!(input: resolved)
        rescue InputMappingResolver::UnknownOutputKey, InputMappingResolver::MissingPath => e
          action_run.update!(status: "failed", error: e.message, finished_at: Time.current)
        end

        action_run
      end

      unless action_runs.any? { |ar| ar.status == "failed" }
        runnable = action_runs.select { |ar| ar.status == "pending" }
        run_actions_in_parallel(runnable) if runnable.any?
      end
      action_runs.each(&:reload)
    end

    def run_actions_in_parallel(action_runs)
      Sync do
        barrier = Async::Barrier.new
        semaphore = Async::Semaphore.new(10, parent: barrier)

        action_runs.each do |action_run|
          semaphore.async { execute_action(action_run) }
        end

        barrier.wait
      end
    end

    def execute_action(action_run)
      action_run.update!(status: "running", started_at: Time.current)
      action = action_run.step_action.action
      execution = run_agent(action_run)
      validate_output!(action, execution[:output], raw_content: execution[:raw_content]) if action.agent?
      action_run.update!(status: "completed", output: execution[:output], error: nil, error_details: nil, finished_at: Time.current)
    rescue StandardError => error
      handle_action_failure(action_run, error, raw_content: execution&.dig(:raw_content))
    end

    def run_agent(action_run)
      action = action_run.step_action.action
      input  = action_run.input || {} # : Hash[String, untyped]

      if action.agent?
        builder = RuntimeAgentBuilder.new(
          action: action,
          pipeline_model: @pipeline_run.pipeline.model,
          prompt_override: prompt_for(action.agent&.name),
          step_params: action_run.step_action.params
        )
        agent = builder.build
        chat_id = agent.respond_to?(:chat) ? agent.chat&.id : agent.id
        action_run.update_columns(chat_id: chat_id, agent_snapshot: builder.snapshot)
        result = agent.ask(builder.resolved_params.merge(input).to_json)
        output = parse_content(result.content, structured_output_expected?(action))
        normalized_output = action.agent&.output_schema.present? ? output : { "result" => output }
        { output: normalized_output, raw_content: result.content }
      else
        klass = action.agent_class&.constantize
        raise ArgumentError, "Service class not found: #{action.agent_class}" unless klass

        params = (action.params || {}).merge(action_run.step_action.params || {})
        { output: klass.call(input, params), raw_content: nil }
      end
    end

    def parse_content(content, structured_output_expected)
      return content unless content.is_a?(String)

      JSON.parse(content)
    rescue JSON::ParserError => error
      raise InvalidModelOutputError.new("Invalid model output: #{error.message}", raw_content: content) if structured_output_expected

      content
    end

    def validate_output!(action, output, raw_content:)
      schema = action.agent&.output_schema
      SchemaValidator.new(schema).validate!(output)
    rescue SchemaValidator::Error => error
      raise error unless structured_output_expected?(action)

      raise InvalidModelOutputError.new("Invalid model output: #{error.message}", raw_content: raw_content)
    end

    def handle_action_failure(action_run, error, raw_content:)
      failure = NormalizeActionRunFailure.call(error:, action_run:, raw_content:)
      action_run.update!(
        status: "failed",
        error: failure.summary,
        error_details: failure.details,
        finished_at: Time.current
      )
      log_action_failure(action_run, failure) if failure.details.present?
    end

    def log_action_failure(action_run, failure)
      details = failure.details || {}

      Rails.logger.error(
        {
          event: "orchestration.action_run_failed",
          category: details["category"],
          provider: details["provider"],
          model: details["model"],
          status_code: details["status_code"],
          action_run_id: action_run.id,
          pipeline_run_id: @pipeline_run.id,
          chat_id: details["chat_id"],
          summary: failure.summary
        }.to_json
      )
    end

    def structured_output_expected?(action)
      action.agent&.output_schema.present?
    end

    def prompt_for(agent_class)
      @prompt_cache ||= {} # : Hash[String?, String?]
      return @prompt_cache[agent_class] if @prompt_cache.key?(agent_class)

      @prompt_cache[agent_class] = Evaluation::Prompt
        .where(name: agent_class)
        .order(version: :desc, id: :desc)
        .first
        &.system_prompt
    end
  end
end
