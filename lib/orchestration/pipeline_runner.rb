module Orchestration
  class PipelineRunner
    include SteepHacks

    def initialize(pipeline_run)
      @pipeline_run = pipeline_run
      @prompt_cache = Hash.new # : Hash[String?, String?]
    end

    def run
      @pipeline_run.update!(status: "running", started_at: Time.current)
      previous_outputs = build_initial_outputs
      process_steps(previous_outputs)
    end

    private

    def build_initial_outputs
      initial_input = @pipeline_run.initial_input
      initial_input.nil? ? Hash.new : { "_initial" => initial_input }
    end

    def process_steps(previous_outputs)
      steps = @pipeline_run.pipeline.enabled_steps.to_a # : Array[Step]
      completed = steps.each do |step|
        action_runs = run_step(step, previous_outputs)
        break if handle_step_failure(action_runs)
        accumulate_step_outputs(action_runs, previous_outputs)
      end
      @pipeline_run.update!(status: "completed", finished_at: Time.current) if completed
    end

    def handle_step_failure(action_runs)
      failed_run = action_runs.find { |ar| ar.status == "failed" }
      return false unless failed_run

      @pipeline_run.update!(status: "failed", error: failed_run.error, finished_at: Time.current)
      true
    end

    def accumulate_step_outputs(action_runs, previous_outputs)
      action_runs.each do |ar|
        previous_outputs[ar.step_action.output_key] = ar.output || empty_object
      end
    end

    def run_step(step, previous_outputs)
      action_runs = prepare_action_runs(step, previous_outputs)
      unless action_runs.any? { |ar| ar.status == "failed" }
        runnable = action_runs.select { |ar| ar.status == "pending" }
        run_actions_in_parallel(runnable) if runnable.any?
      end
      action_runs.each(&:reload)
    end

    def prepare_action_runs(step, previous_outputs)
      step.step_actions.to_a.map do |step_action| # : Array[StepAction]
        action_run = create_action_run(step_action)
        resolve_action_input(action_run, step_action, previous_outputs)
        action_run
      end
    end

    def create_action_run(step_action)
      empty_input = empty_object # : json_object
      @pipeline_run.action_runs.create!(step_action: step_action, status: "pending", input: empty_input) # : ActionRun
    end

    def resolve_action_input(action_run, step_action, previous_outputs)
      resolved = InputMappingResolver.new(
        input_mapping: step_action.input_mapping || empty_object,
        previous_outputs: previous_outputs
      ).resolve
      action_run.update!(input: resolved)
    rescue InputMappingResolver::UnknownOutputKey, InputMappingResolver::MissingPath => e
      action_run.update!(status: "failed", error: e.message, finished_at: Time.current)
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
      ActionExecutor.new(action_run:, pipeline_run: @pipeline_run, prompt_cache: @prompt_cache).call
    end
  end
end
