
module Orchestration
  class StepsController < ApplicationController
    before_action :set_pipeline
    before_action :set_step, only: [ :update, :destroy, :move_up, :move_down, :toggle ]

    def create
      steps         = @pipeline.steps
      next_position = (steps.maximum(:position) || 0) + 1
      @step = steps.build(step_params.merge(position: next_position))
      if @step.save
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Step added."
      else
        render_pipeline_show
      end
    end

    def update
      if @step.update(step_params)
        redirect_to orchestration_pipeline_path(@pipeline), notice: "Step updated."
      else
        render_pipeline_show
      end
    end

    def destroy
      @step.destroy
      redirect_to orchestration_pipeline_path(@pipeline), notice: "Step removed."
    end

    def move_up
      prev_step = @step.previous_sibling
      @step.swap_position_with(prev_step) if prev_step
      redirect_to orchestration_pipeline_path(@pipeline)
    end

    def move_down
      next_step = @step.next_sibling
      @step.swap_position_with(next_step) if next_step
      redirect_to orchestration_pipeline_path(@pipeline)
    end

    def toggle
      @step.update!(enabled: !@step.enabled)
      redirect_to orchestration_pipeline_path(@pipeline)
    end

    private

    def set_pipeline
      @pipeline = Orchestration::Pipeline.find(params[:pipeline_id])
    end

    def set_step
      @step = @pipeline.steps.find(params[:id])
    end

    def render_pipeline_show
      @steps = @pipeline.steps_with_actions
      @actions = Orchestration::Action.order(:name)
      render "orchestration/pipelines/show", status: :unprocessable_content
    end

    def step_params
      params.expect(orchestration_step: [ :name ])
    end
  end
end
