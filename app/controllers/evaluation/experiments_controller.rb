# frozen_string_literal: true

module Evaluation
  class ExperimentsController < ApplicationController
    before_action :set_experiment, only: [ :show, :improve, :compare, :activate, :status_frame, :metric_results ]

    WIZARD_STEPS = 4

    def index
      @experiments = Experiment.order(created_at: :desc).includes(:prompt)
    end

    def new
      @draft = find_or_create_draft
      @step  = (params[:step] || @draft.step).to_i.clamp(1, WIZARD_STEPS)
      load_step_data(@step)
    end

    def wizard_step
      @draft = find_or_create_draft
      current_step = params[:current_step].to_i

      if current_step >= WIZARD_STEPS
        create_experiment_from_draft(@draft)
      else
        @draft.advance!(current_step + 1, step_payload(current_step))
        redirect_to new_evaluation_experiment_path(step: @draft.step)
      end
    end

    def create
      wizard_step
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

    def show
      @agent_name = @experiment.prompt&.name
      @metrics = @agent_name ? Metric.for_agent(@agent_name).order(:name) : Evaluation::Metric.none
      @runner_result_count = @experiment.runner_results.count
      @per_metric_avg = per_metric_averages(@experiment)

      meta = @experiment.metadata || {}
      agent = @agent_name ? Orchestration::Agent.find_by(name: @agent_name) : nil
      @runner_model = meta["pipeline_model"].presence || agent&.model.presence
      @judge_model  = Evaluators::LLMJudgeEval.judge_model

      return unless @experiment.prompt

      @newer_experiment = Experiment
        .joins(:prompt)
        .where(evaluation_prompts: { name: @experiment.prompt.name })
        .where("evaluation_experiments.id > ?", @experiment.id)
        .order(id: :desc)
        .includes(:prompt)
        .first
    end

    def status_frame
      render partial: "status_badge", locals: { experiment: @experiment, with_src: false }
    end

    def metric_results
      @metric_name = params[:metric_name]
      @justifications = Justification
        .joins(:evaluation_result)
        .where(metric_name: @metric_name, evaluation_evaluation_results: { experiment_id: @experiment.id })
        .includes(evaluation_result: [ :runner_result, :dataset_record ])
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

    def find_or_create_draft
      token = session[:wizard_token] ||= SecureRandom.hex(16)
      WizardDraft.find_or_create_for_token(token)
    end

    def step_payload(step)
      case step
      when 1 then params.require(:wizard).permit(:agent_name, :prompt_id, :experiment_name, :sample_model, :evaluation_model).to_h
      when 2 then {}
      when 3 then params.require(:wizard).permit(:dataset_id).to_h
      else {}
      end
    end

    def load_step_data(step)
      payload = @draft.payload || {}
      @form = case step
      when 1 then Evaluation::Wizard::Step1Form.new(draft_payload: payload)
      when 2 then Evaluation::Wizard::Step2Form.new(draft_payload: payload)
      when 3 then Evaluation::Wizard::Step3Form.new(draft_payload: payload, draft_token: session[:wizard_token])
      when 4 then Evaluation::Wizard::Step4Form.new(draft_payload: payload)
      end
    end

    def create_experiment_from_draft(draft)
      experiment = CreateExperimentFromDraft.call(draft: draft)
      session.delete(:wizard_token)
      redirect_to evaluation_experiment_path(experiment), notice: "Experiment '#{experiment.name}' started."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      @draft = draft
      @step  = 4
      load_step_data(4)
      render :new, status: :unprocessable_entity
    end

    def per_metric_averages(experiment)
      EvaluationResult.per_metric_averages(experiment)
    end
  end
end
