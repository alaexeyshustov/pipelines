# frozen_string_literal: true

module Evaluation
  class ExperimentsController < ApplicationController
    before_action :set_experiment, only: [ :show, :improve, :compare, :activate, :status_frame, :metric_results, :destroy ]

    def index
      @experiments = Experiment.order(created_at: :desc).includes(:prompt)
    end

    def new
      @wizard_form = build_wizard_form(step_param: params[:step])
    end

    def show; end

    def create
      @wizard_form = build_wizard_form(step_param: params[:current_step])

      if @wizard_form.complete? && @wizard_form.valid?
        experiment = @wizard_form.complete!
        session.delete(:wizard_token)
        redirect_to evaluation_experiment_path(experiment), notice: "Experiment '#{experiment.name}' started."
      elsif @wizard_form.complete?
        render_wizard_error
      else
        if @wizard_form.advance!(@wizard_form.step, wizard_params)
          redirect_to new_evaluation_experiment_path(step: @wizard_form.step + 1)
        else
          render_wizard_error
        end
      end
    end

    def destroy
      if @experiment.in_progress?
        return redirect_to evaluation_experiments_path, alert: "Cannot delete an experiment that is in progress."
      end

      @experiment.destroy!
      redirect_to evaluation_experiments_path, notice: "Experiment '#{@experiment.name}' deleted."
    end

    def snapshot_agent_prompt
      agent = Orchestration::Agent.find_by(name: params[:agent_name])

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

      prompt = Evaluation::Prompt.create!(
        name: based_on.name,
        system_prompt: fork_prompt_params[:system_prompt] || based_on.system_prompt,
        user_prompt:   fork_prompt_params[:user_prompt]   || based_on.user_prompt,
        output_schema: fork_prompt_params[:output_schema] || based_on.output_schema
      )
      render json: { id: prompt.id, version: prompt.version }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    def prompt_versions
      prompts = Prompt
        .where(name: params[:agent_name])
        .order(version: :desc)
        .select(:id, :version, :metadata)
      render json: prompts.map { |p|
        meta = begin; JSON.parse(p.metadata || "{}"); rescue JSON::ParserError; {}; end
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
      unless @experiment.prompt
        return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt."
      end

      new_prompt = PromptImprover.call(experiment: @experiment)
      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt improvement triggered. Evaluating prompt v#{new_prompt.version}…"
    rescue PromptImprover::Error => e
      logger.error("PromptImprover failed for experiment #{@experiment.id}: #{e.message}")
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    rescue ArgumentError => e
      logger.error("PromptImprover argument error for experiment #{@experiment.id}: #{e.message}")
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    end

    def compare
      @candidate = Experiment
        .joins(:prompt)
        .where(evaluation_prompts: { name: @experiment.prompt&.name })
        .where.not(id: @experiment.id)
        .find_by(id: params[:candidate_id])

      unless @candidate
        return redirect_to evaluation_experiment_path(@experiment), alert: "Candidate experiment not found."
      end

      return unless @candidate.completed?

      @result = Comparison.call(
        baseline_experiment: @experiment,
        candidate_experiment: @candidate
      )
    end

    def activate
      prompt = @experiment.prompt
      unless prompt
        return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt."
      end

      meta = JSON.parse(prompt.metadata || "{}")
      prompt.update!(metadata: meta.merge("active" => true).to_json)

      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt v#{prompt.version} activated for #{prompt.name}."
    end

    private

    def set_experiment
      @experiment = Experiment.find(params[:id])
    end

    def build_wizard_form(step_param: nil)
      token = session[:wizard_token] ||= SecureRandom.hex(16)
      WizardForm.new(wizard_token: token, step_param: step_param)
    end

    def fork_prompt_params
      params.permit(:based_on_prompt_id, :system_prompt, :user_prompt, :output_schema)
    end

    def wizard_params
      params.fetch(:wizard, {}).permit(:agent_name, :prompt_id, :experiment_name, :sample_model, :evaluation_model, :dataset_id).to_h
    end

    def render_wizard_error
      flash.now[:alert] = @wizard_form.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end
end
