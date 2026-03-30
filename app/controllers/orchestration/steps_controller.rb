# frozen_string_literal: true

module Orchestration
  class StepsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step, only: [ :update, :destroy, :move_up, :move_down ]

    def create
      next_position = (@pipeline.steps.maximum(:position) || 0) + 1
      @step = @pipeline.steps.build(step_params.merge(position: next_position))
      if @step.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Step added."
      else
        @steps = @pipeline.steps.includes(step_actions: :action)
        @actions = Orchestration::Action.order(:name)
        render "orchestration/pipelines/show", status: :unprocessable_entity
      end
    end

    def update
      if @step.update(step_params)
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Step updated."
      else
        @steps = @pipeline.steps.includes(step_actions: :action)
        @actions = Orchestration::Action.order(:name)
        render "orchestration/pipelines/show", status: :unprocessable_entity
      end
    end

    def destroy
      @step.destroy
      redirect_to orchestration_pipeline_path(@pipeline), notice: "Step removed."
    end

    def move_up
      prev_step = @pipeline.steps.where("position < ?", @step.position).order(position: :desc).first
      swap_positions(@step, prev_step) if prev_step
      redirect_to orchestration_pipeline_path(@pipeline)
    end

    def move_down
      next_step = @pipeline.steps.where("position > ?", @step.position).order(position: :asc).first
      swap_positions(@step, next_step) if next_step
      redirect_to orchestration_pipeline_path(@pipeline)
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.find(params[:pipeline_id])
    end

    def set_step
      @step = @pipeline.steps.find(params[:id])
    end

    def step_params
      parsed = params.require(:orchestration_step).permit(:name, :input_mapping)
      if parsed[:input_mapping].present?
        parsed[:input_mapping] = JSON.parse(parsed[:input_mapping])
      end
      parsed
    rescue JSON::ParserError
      params.require(:orchestration_step).permit(:name, :input_mapping)
    end

    def swap_positions(step_a, step_b)
      pos_a = step_a.position
      pos_b = step_b.position
      temp = @pipeline.steps.maximum(:position) + 1

      ActiveRecord::Base.transaction do
        step_a.update_column(:position, temp)
        step_b.update_column(:position, pos_a)
        step_a.update_column(:position, pos_b)
      end
    end
  end
end
