# frozen_string_literal: true

module Evaluation
  class ExperimentsController < ApplicationController
    before_action :set_experiment, only: [ :show, :improve, :compare, :activate, :status_frame, :metric_results ]

    WIZARD_STEPS = 4

    def index
      @experiments = Leva::Experiment.order(created_at: :desc).includes(:prompt)
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
      prompts = Orchestration::Prompt
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
      @metrics = @agent_name ? Evaluation::Metric.for_agent(@agent_name).order(:name) : Evaluation::Metric.none
      @runner_result_count = @experiment.runner_results.count
      @per_metric_avg = per_metric_averages(@experiment)

      meta = @experiment.metadata || {}
      agent = @agent_name ? Orchestration::Agent.find_by(name: @agent_name) : nil
      @runner_model = meta["pipeline_model"].presence || agent&.model.presence
      @judge_model  = LLMJudgeEval.judge_model

      return unless @experiment.prompt

      @newer_experiment = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: @experiment.prompt.name })
        .where("leva_experiments.id > ?", @experiment.id)
        .order(id: :desc)
        .includes(:prompt)
        .first
    end

    def status_frame
      render partial: "status_badge", locals: { experiment: @experiment, with_src: false }
    end

    def metric_results
      @metric_name = params[:metric_name]
      @justifications = Evaluation::Justification
        .joins(:evaluation_result)
        .where(metric_name: @metric_name, leva_evaluation_results: { experiment_id: @experiment.id })
        .includes(evaluation_result: [ :runner_result, :dataset_record ])
        .order("leva_evaluation_results.score DESC")
    end

    def improve
      unless @experiment.prompt
        return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt."
      end

      new_prompt = Evaluation::PromptImprover.call(experiment: @experiment)
      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt improvement triggered. Evaluating prompt v#{new_prompt.version}…"
    rescue Evaluation::PromptImprover::Error => e
      logger.error("PromptImprover failed for experiment #{@experiment.id}: #{e.message}")
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    rescue ArgumentError => e
      logger.error("PromptImprover argument error for experiment #{@experiment.id}: #{e.message}")
      redirect_to evaluation_experiment_path(@experiment), alert: "Prompt improvement failed. Please try again later."
    end

    def compare
      @candidate = Leva::Experiment
        .joins(:prompt)
        .where(leva_prompts: { name: @experiment.prompt&.name })
        .where.not(id: @experiment.id)
        .find_by(id: params[:candidate_id])

      unless @candidate
        return redirect_to evaluation_experiment_path(@experiment), alert: "Candidate experiment not found."
      end

      return unless @candidate.completed?

      @result = Evaluation::Comparison.call(
        baseline_experiment: @experiment,
        candidate_experiment: @candidate
      )
    end

    def activate
      leva_prompt = @experiment.prompt
      unless leva_prompt
        return redirect_to evaluation_experiment_path(@experiment), alert: "This experiment has no associated prompt."
      end

      # Reload as Orchestration::Prompt so update! calls go through our subclass
      prompt = Orchestration::Prompt.find(leva_prompt.id)

      Orchestration::Prompt.transaction do
        Orchestration::Prompt.where(name: prompt.name).where.not(id: prompt.id).find_each do |p|
          meta = begin
            JSON.parse(p.metadata || "{}")
          rescue JSON::ParserError => e
            logger.warn("Could not parse metadata for prompt #{p.id}: #{e.message}")
            next
          end
          meta.delete("active")
          p.update!(metadata: meta.to_json)
        end

        meta = begin
          JSON.parse(prompt.metadata || "{}")
        rescue JSON::ParserError => e
          logger.warn("Could not parse metadata for prompt #{prompt.id}: #{e.message}")
          raise ActiveRecord::Rollback
        end
        meta["active"] = true
        prompt.update!(metadata: meta.to_json)
      end

      redirect_to evaluation_experiment_path(@experiment),
                  notice: "Prompt v#{prompt.version} activated for #{prompt.name}."
    end

    private

    def set_experiment
      @experiment = Leva::Experiment.find(params[:id])
    end

    def find_or_create_draft
      token = session[:wizard_token] ||= SecureRandom.hex(16)
      Evaluation::WizardDraft.find_or_create_for_token(token)
    end

    def step_payload(step)
      case step
      when 1 then params.require(:wizard).permit(:agent_name, :prompt_id, :experiment_name).to_h
      when 2 then {}
      when 3 then params.require(:wizard).permit(:dataset_id).to_h
      else {}
      end
    end

    def load_step_data(step)
      payload = @draft.payload || {}
      case step
      when 1
        @agent_names     = Orchestration::Prompt.distinct.pluck(:name).sort
        @prompts         = Orchestration::Prompt.order(version: :desc)
        @agent_name      = payload["agent_name"]
        @prompt_id       = payload["prompt_id"]
        @experiment_name = payload["experiment_name"]
      when 2
        @agent_name = payload["agent_name"]
        @metrics    = Evaluation::Metric.for_agent(@agent_name).order(:name)
      when 3
        @agent_name = payload["agent_name"]
        @datasets   = Leva::Dataset.left_joins(:dataset_records)
                                   .group("leva_datasets.id")
                                   .select("leva_datasets.*, COUNT(leva_dataset_records.id) AS record_count")
                                   .order(:name)
        @selected_dataset_id = payload["dataset_id"]
      when 4
        @agent_name      = payload["agent_name"]
        @prompt          = Leva::Prompt.find_by(id: payload["prompt_id"])
        @experiment_name = payload["experiment_name"]
        @metrics_count   = Evaluation::Metric.for_agent(@agent_name).active.count
        @dataset         = Leva::Dataset.find_by(id: payload["dataset_id"])
      end
    end

    def create_experiment_from_draft(draft)
      payload    = draft.payload || {}
      prompt_id  = payload["prompt_id"].presence ||
                   Orchestration::Prompt
                     .where(name: payload["agent_name"])
                     .order(version: :desc, id: :desc)
                     .pick(:id)
                     &.to_s
      agent_name = Orchestration::Prompt.find_by(id: prompt_id)&.name

      if agent_name.present? && Evaluation::Metric.for_agent(agent_name).active.none?
        begin
          auto_generate_metrics(agent_name)
        rescue Evaluation::MetricSuggester::Error => e
          logger.warn("MetricSuggester failed for #{agent_name}: #{e.message} — proceeding without auto-generated metrics")
        end
      end

      experiment = Leva::Experiment.create!(
        name:              payload["experiment_name"].presence || "Manual eval",
        dataset_id:        payload["dataset_id"],
        prompt_id:         prompt_id,
        runner_class:      "StubbedAgentRun",
        evaluator_classes: [ "LLMJudgeEval" ],
        metadata:          { "triggered_by" => "manual" }
      )
      Leva::ExperimentJob.perform_later(experiment)
      draft.destroy
      session.delete(:wizard_token)
      redirect_to evaluation_experiment_path(experiment), notice: "Experiment '#{experiment.name}' started."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.message
      @draft = draft
      @step  = 4
      load_step_data(4)
      render :new, status: :unprocessable_entity
    end

    def auto_generate_metrics(agent_name)
      suggestions = Evaluation::MetricSuggester.call(agent_name: agent_name)
      suggestions.each do |s|
        Evaluation::Metric.find_or_initialize_by(agent_name: agent_name, name: s[:name]).tap do |m|
          m.description = s[:description]
          m.weight      = s[:weight]
          m.active      = true
          m.save!
        end
      end
    end

    def per_metric_averages(experiment)
      conn = Leva::EvaluationResult.connection
      results_table        = conn.quote_table_name(Leva::EvaluationResult.table_name)
      justifications_table = conn.quote_table_name(Evaluation::Justification.table_name)

      Leva::EvaluationResult
        .joins(
          "INNER JOIN #{justifications_table} " \
          "ON #{justifications_table}.evaluation_result_id = #{results_table}.id"
        )
        .where(experiment: experiment)
        .group("#{justifications_table}.metric_name")
        .average("#{results_table}.score")
        .transform_keys(&:to_s)
    end
  end
end
