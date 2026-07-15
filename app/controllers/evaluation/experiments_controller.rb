# frozen_string_literal: true

module Evaluation
  class ExperimentsController < ApplicationController
    include Evaluation::ExperimentWizard

    before_action :set_experiment, only: [ :show, :improve, :compare, :activate, :status_frame, :metric_results, :destroy ]

    def index
      @experiments = Experiment.order(created_at: :desc).includes(:prompt)
    end

    def show; end
    def new
      @wizard_form = build_wizard_form(step_param: params[:step])
    end

    def create
      @wizard_form = build_wizard_form(step_param: params[:current_step])
      @wizard_form.complete? ? complete_wizard_or_error : advance_wizard_or_error
    end

    def destroy
      if @experiment.pending? || @experiment.in_progress?
        return redirect_to evaluation_experiments_path, alert: "Cannot delete an experiment that is still running."
      end

      @experiment.destroy!
      redirect_to evaluation_experiments_path, notice: "Experiment '#{@experiment.name}' deleted."
    end

    def snapshot_agent_prompt
      agent = Orchestration::AgentCatalog.find(params[:agent_name])

      if agent.nil? || agent.prompt.blank?
        render json: { error: "Agent not found or has no prompt" }, status: :unprocessable_content
        return
      end

      prompt = Evaluation::Prompt.create!(
        name: agent.name,
        system_prompt: agent.prompt,
        user_prompt: "{{input}}",
        output_schema: agent.output_schema
      )

      render json: { id: prompt.id, version: prompt.version }
    end

    def prompt_content
      prompt = Prompt.find_by(id: params[:prompt_id])
      unless prompt
        render json: { error: "Prompt not found" }, status: :not_found
        return
      end
      render json: { system_prompt: prompt.system_prompt, user_prompt: prompt.user_prompt, output_schema: prompt.output_schema }
    end

    def fork_prompt
      based_on = Prompt.find_by(id: params[:based_on_prompt_id])
      unless based_on
        render json: { error: "Base prompt not found" }, status: :unprocessable_content
        return
      end

      prompt = fork_prompt_record(based_on)
      render json: { id: prompt.id, version: prompt.version }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def prompt_versions
      prompts = Prompt.metadata_versions_for(params[:agent_name])
      render json: prompts.map { |p|
        meta = JSON::Helpers.safe_parse(p.metadata, fallback: {})
        { id: p.id, version: p.version, active: meta["active"] == true }
      }
    end

    def status_frame
      render Evaluation::Experiments::StatusBadgeComponent.new(experiment: @experiment, with_src: false)
    end

    def metric_results
      @metric_name = params[:metric_name]
      @justifications = Justification
        .joins(:evaluation_result)
        .where(metric_name: @metric_name, evaluation_evaluation_results: { experiment_id: @experiment.id })
        .includes(evaluation_result: [ :sample, :dataset_sample ])
        .order("evaluation_evaluation_results.score DESC")
    end

    def improve
      return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt." unless @experiment.prompt

      new_prompt = PromptImprover.call(experiment: @experiment)
      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt improvement triggered. Evaluating prompt v#{new_prompt.version}…"
    rescue PromptImprover::Error => e
      redirect_after_improve_failure("PromptImprover failed", e)
    rescue ArgumentError => e
      redirect_after_improve_failure("PromptImprover argument error", e)
    end

    def compare
      @candidate = Experiment
        .sibling_for_prompt_name(@experiment.prompt&.name, excluding_id: @experiment.id)
        .find_by(id: params[:candidate_id])

      return redirect_to evaluation_experiment_path(@experiment), alert: "Candidate experiment not found." unless @candidate
      return unless @candidate.completed?

      @result = Comparison.call(
        baseline_experiment: @experiment,
        candidate_experiment: @candidate
      )
    end

    def activate
      prompt = @experiment.prompt
      return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt." unless prompt

      meta = JSON.parse(prompt.metadata || "{}")
      prompt.update!(metadata: meta.merge("active" => true).to_json)

      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt v#{prompt.version} activated for #{prompt.name}."
    end

    private

    def set_experiment
      @experiment = Experiment.find(params[:id])
    end

    def redirect_after_improve_failure(context, e)
      Evaluation::ImproveFailureLogger.call(context: context, experiment: @experiment, error: e)
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    end
  end
end
