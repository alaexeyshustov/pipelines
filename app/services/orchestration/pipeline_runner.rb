module Orchestration
  class PipelineRunner
    include SteepHacks

    def initialize(pipeline_run)
      @pipeline_run = pipeline_run
    end

    def call
      @pipeline_run.update!(status: "running", started_at: Time.current)

      initial_input = @pipeline_run.initial_input
      previous_outputs = initial_input.nil? ? Hash.new : { "_initial" => initial_input }

      steps_rel = @pipeline_run.pipeline.steps.where(enabled: true) # : ActiveRecord::Relation
      steps = steps_rel.order(:position).to_a # : Array[Step]
      steps.each do |step|
        action_runs = run_step(step, previous_outputs)

        failed_run = action_runs.find { |ar| ar.status == "failed" }
        if failed_run
          @pipeline_run.update!(status: "failed", error: failed_run.error, finished_at: Time.current)
          return
        end

        action_runs.each do |ar|
          previous_outputs[ar.step_action.output_key] = ar.output || empty_object
        end
      end

      @pipeline_run.update!(status: "completed", finished_at: Time.current)
    end

    private

    def run_step(step, previous_outputs)
      step_actions = step.step_actions.to_a # : Array[StepAction]
      action_runs = step_actions.map do |step_action|
        empty_input = empty_object # : json_object
        action_run = @pipeline_run.action_runs.create!(step_action: step_action, status: "pending", input: empty_input) # : ActionRun

        begin
          resolved = InputMappingResolver.new(
            input_mapping: step_action.input_mapping || empty_object,
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
      policy = action.agent? ? resolve_policy(action_run) : nil

      validate_input_schema!(action_run)

      execution = run_agent(action_run, policy: policy)
      if action.agent?
        raise ArgumentError, "policy missing for agent action" unless policy
        validate_output!(execution[:output], policy: policy, raw_content: execution[:raw_content])
      end
      action_run.update!(status: "completed", output: execution[:output], error: nil, error_details: nil, finished_at: Time.current)
    rescue StandardError => error
      handle_action_failure(action_run, error, raw_content: execution&.dig(:raw_content))
    end

    def validate_input_schema!(action_run)
      schema = action_run.step_action.action.input_schema
      return unless schema

      SchemaValidator.new(schema).validate!(action_run.input || empty_object)
    end

    def run_agent(action_run, policy: nil)
      action = action_run.step_action.action
      input  = action_run.input || empty_object # : json_object

      if action.agent?
        raise ArgumentError, "policy missing for agent action" unless policy
        builder = RuntimeAgentBuilder.new(policy: policy)
        agent = builder.build
        chat_id = agent.chat&.id
        snapshot = {
          model: policy.model,
          prompt: policy.prompt,
          tools: policy.tools&.map(&:to_s) || [],
          output_schema: policy.output_schema
        }
        action_run.update_columns(chat_id: chat_id, agent_snapshot: snapshot)
        result = agent.ask(input.to_json)
        output = parse_content(result.content, policy.output_schema.present?)
        normalized_output = if policy.output_schema.present?
          output
        else
          { "result" => output.nil? && result.content.is_a?(String) ? result.content : output }
        end
        { output: normalized_output, raw_content: result.content }
      else
        klass = ServiceRegistry.lookup(action.agent_class)
        raise ArgumentError, "Service class not found: #{action.agent_class}" unless klass

        { output: klass.call(**input.transform_keys(&:to_sym)), raw_content: nil }
      end
    end

    def resolve_policy(action_run)
      action = action_run.step_action.action
      AgentResolutionPolicy.call(
        action: action,
        pipeline_model: @pipeline_run.pipeline.model,
        prompt_override: prompt_for(action.agent&.name)
      )
    end

    def parse_content(content, structured_output_expected)
      if content.is_a?(Hash)
        return content.transform_keys(&:to_s)
      end

      unless content.is_a?(String)
        raise InvalidModelOutputError.new("Invalid model output: expected JSON object", raw_content: content) if structured_output_expected

        return nil
      end

      parsed = JSON.parse(content)
      return parsed.transform_keys(&:to_s) if parsed.is_a?(Hash)

      raise InvalidModelOutputError.new("Invalid model output: expected JSON object", raw_content: parsed) if structured_output_expected

      nil
    rescue JSON::ParserError => error
      raise InvalidModelOutputError.new("Invalid model output: #{error.message}", raw_content: content) if structured_output_expected

      nil
    end

    def validate_output!(output, policy:, raw_content:)
      SchemaValidator.new(policy.output_schema).validate!(output)
    rescue SchemaValidator::Error => error
      raise error unless policy.output_schema.present?

      raise InvalidModelOutputError.new(error.message, raw_content: raw_content)
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
      details = failure.details || empty_object

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

    def prompt_for(agent_class)
      @prompt_cache ||= Hash.new
      return @prompt_cache[agent_class] if @prompt_cache.key?(agent_class)

      @prompt_cache[agent_class] = Evaluation::Prompt
        .where(name: agent_class)
        .order(version: :desc, id: :desc)
        .first
        &.system_prompt
    end
  end
end
