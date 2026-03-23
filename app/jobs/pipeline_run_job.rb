class PipelineRunJob < ApplicationJob
  def perform(pipeline_run_id)
    pipeline_run = Orchestration::PipelineRun.find(pipeline_run_id)
    pipeline_run.update!(status: "running", started_at: Time.current)

    steps = pipeline_run.pipeline.steps.order(:position)
    previous_outputs = []

    steps.each do |step|
      resolved_input = Orchestration::InputMappingResolver.new(
        input_mapping: step.input_mapping,
        previous_outputs: previous_outputs
      ).resolve

      action_runs = step.step_actions.map do |step_action|
        pipeline_run.action_runs.create!(
          step_action: step_action,
          status: "pending",
          input: resolved_input
        )
      end

      run_actions_in_parallel(action_runs)

      action_runs.each(&:reload)

      failed_run = action_runs.find { |ar| ar.status == "failed" }
      if failed_run
        pipeline_run.update!(status: "failed", error: failed_run.error, finished_at: Time.current)
        return
      end

      previous_outputs = action_runs.map do |ar|
        { "step_name" => step.name, "output" => ar.output || {} }
      end
    end

    pipeline_run.update!(status: "completed", finished_at: Time.current)
  end

  private

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
    step_action = action_run.step_action
    action      = step_action.action

    action_run.update!(status: "running", started_at: Time.current)

    params = (action.params || {}).merge(step_action.params || {})
    agent  = build_agent(action, params)

    input_text = action_run.input.to_json
    result     = agent.ask(input_text)

    action_run.update!(
      status: "completed",
      output: { "result" => result.to_s },
      finished_at: Time.current
    )
  rescue StandardError => e
    action_run.update!(status: "failed", error: e.message, finished_at: Time.current)
    raise
  end

  def build_agent(action, _params)
    agent = action.agent_class.constantize.new

    agent = agent.with_model(action.model) if action.model.present?
    agent = agent.with_tools(*action.tools) if action.tools.present?

    if action.prompt.present?
      agent.chat.with_instructions(action.prompt)
    end

    agent
  end
end
