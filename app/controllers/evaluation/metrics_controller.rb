module Evaluation
  class MetricsController < ApplicationController
    before_action :set_metric, only: [ :edit, :update, :destroy ]

    def index
      @metrics_by_agent = Evaluation::Metric.order(:agent_name, :name).group_by(&:agent_name)
    end

    def edit
    end

    def create
      @metric = Evaluation::Metric.new(metric_attributes)
      @metric.save ? render_metric_created : render_metric_form_error
    end
    def update
      if @metric.update(metric_attributes)
        redirect_to evaluation_metrics_path, notice: "Metric updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @metric.destroy
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove("evaluation_metric_#{@metric.id}") }
        format.html { redirect_to evaluation_metrics_path, notice: "Metric deleted." }
      end
    end

    def generate
      suggestions = Evaluation::MetricSuggester.call(agent_name: params[:agent_name])
      render partial: "evaluation/metrics/suggestions",
             locals: { suggestions: suggestions, agent_name: params[:agent_name] }
    rescue Evaluation::MetricSuggester::Error => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def render_metric_created
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "metrics-list-#{@metric.agent_name}",
            partial: "evaluation/metrics/metric_card",
            locals: { metric: @metric }
          )
        end
        format.html { redirect_to evaluation_metrics_path, notice: "Metric created." }
      end
    end

    def render_metric_form_error
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "metric-form",
            partial: "evaluation/metrics/new_form",
            locals: { metric: @metric }
          ), status: :unprocessable_content
        end
        format.html do
          render partial: "evaluation/metrics/new_form",
                 locals: { metric: @metric }, status: :unprocessable_content
        end
      end
    end

    def set_metric
      @metric = Evaluation::Metric.find(params[:id])
    end

    def metric_params
      params.expect(evaluation_metric: [ :agent_name, :name, :description, :weight, :active, :kind, :minimum, :levels_text ])
    end

    # levels_text (one line per level / option, see MetricLevelsText) becomes Metric#levels; absent keeps the stored levels.
    def metric_attributes
      attributes = metric_params.to_h.symbolize_keys
      text = attributes.delete(:levels_text)
      return attributes if text.nil?

      kind = attributes[:kind] || @metric&.kind
      attributes.merge(levels: MetricLevelsText.parse(kind: kind, text: text))
    end
  end
end
