module Orchestration
  class PipelineRunner
    def initialize(pipeline_run)
      @pipeline_run = pipeline_run
    end

    def call
      @pipeline_run.update!(status: "running", started_at: Time.current)

      previous_outputs = [] # : Array[Orchestration::InputMappingResolver::previous_output_entry]
      previous_outputs << { "step_name" => "initial", "output" => @pipeline_run.initial_input } if @pipeline_run.initial_input.present?

      @pipeline_run.pipeline.steps.where(enabled: true).order(:position).each do |step|
        resolved_input = InputMappingResolver.new(
          input_mapping: step.input_mapping,
          previous_outputs: previous_outputs
        ).resolve

        action_runs = run_step(step, resolved_input)

        failed_run = action_runs.find { |ar| ar.status == "failed" }
        if failed_run
          @pipeline_run.update!(status: "failed", error: failed_run.error, finished_at: Time.current)
          return
        end

        previous_outputs += action_runs.map do |ar|
          { "step_name" => step.name, "output" => ar.output || {} }
        end
      end

      @pipeline_run.update!(status: "completed", finished_at: Time.current)
    end

    private

    def run_step(step, resolved_input)
      action_runs = step.step_actions.map do |step_action|
        @pipeline_run.action_runs.create!(
          step_action: step_action,
          status: "pending",
          input: resolved_input
        )
      end

      run_actions_in_parallel(action_runs)
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
      output = run_agent(action_run)
      validate_output!(action_run.step_action.action, output)
      action_run.update!(status: "completed", output: output, finished_at: Time.current)
    rescue StandardError => error
      action_run.update!(status: "failed", error: error.message, finished_at: Time.current)
    end

    def run_agent(action_run)
      action = action_run.step_action.action
      klass  = action.agent_class&.constantize
      raise ArgumentError, "Agent class not found: #{action.agent_class}" unless klass

      input  = action_run.input
      if klass.ancestors.include?(RubyLLM::Agent)
        params = (action.params || {}).merge(action_run.step_action.params || {})
        agent = build_agent(action, params)
        chat_id = agent.respond_to?(:chat) ? agent.chat&.id : agent.id
        # Persist before ask so chat_id is saved even if the agent raises
        action_run.update_column(:chat_id, chat_id)
        result = agent.ask(input.to_json)
        { "result" => parse_content(result.content) }
      else
        params = (action.params || {}).merge(action_run.step_action.params || {})
        klass.call(input, params)
      end
    end

    def parse_content(content)
      return content unless content.is_a?(String)

      JSON.parse(content)
    rescue JSON::ParserError
      content
    end

    def validate_output!(action, output)
      OutputValidator.new(action.output_schema).validate!(output)
    end

    def build_agent(action, _params)
      model        = @pipeline_run.pipeline.model.presence || action.model
      tools        = action.tools
      prompt       = action.prompt
      schema_class = action.schema_class
      agent_class  = action.agent_class
      raise ArgumentError, "Agent class not found: #{agent_class}" unless agent_class.present?

      # agent = agent_class.constantize.new
      agent = agent_class.constantize.create
      agent = agent.with_model(model)                    if model.present? && agent.respond_to?(:with_model)
      agent = agent.with_tools(*tools)                   if tools.present?
      agent = agent.with_schema(schema_class.constantize) if schema_class.present?
      agent.chat.with_instructions(prompt)               if prompt.present? && agent.respond_to?(:chat)
      agent
    end
  end
end
