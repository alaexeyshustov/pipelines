module Orchestration
  class PipelineRunner
    def initialize(pipeline_run)
      @pipeline_run = pipeline_run
    end

    def call
      @pipeline_run.update!(status: "running", started_at: Time.current)

      previous_outputs = []

      @pipeline_run.pipeline.steps.order(:position).each do |step|
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

        previous_outputs = action_runs.map do |ar|
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
      Async do
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
      result = run_agent(action_run)
      action_run.update!(status: "completed", output: { "result" => result.to_s }, finished_at: Time.current)
    rescue StandardError => error
      action_run.update!(status: "failed", error: error.message, finished_at: Time.current)
    end

    def run_agent(action_run)
      step_action = action_run.step_action
      action      = step_action.action
      params      = (action.params || {}).merge(step_action.params || {})
      agent       = build_agent(action, params)
      agent.ask(action_run.input.to_json)
    end

    def build_agent(action, _params)
      model  = action.model
      tools  = action.tools
      prompt = action.prompt

      agent = action.agent_class.constantize.new
      agent = agent.with_model(model) if model.present?
      agent = agent.with_tools(*tools) if tools.present?
      agent.chat.with_instructions(prompt) if prompt.present?
      agent
    end
  end
end
