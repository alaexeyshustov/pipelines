# frozen_string_literal: true

module Evaluation
  class MetricsController < ApplicationController
    before_action :set_metric, only: [ :edit, :update ]

    def index
      @metrics_by_agent = Evaluation::Metric.order(:agent_name, :name).group_by(&:agent_name)
    end

    def edit
    end

    def update
      if @metric.update(metric_params)
        redirect_to evaluation_metrics_path, notice: "Metric updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_metric
      @metric = Evaluation::Metric.find(params[:id])
    end

    def metric_params
      params.require(:evaluation_metric).permit(:description, :weight, :active)
    end
  end
end
