# frozen_string_literal: true

module Orchestration
  class AllPipelineRunsController < ApplicationController
    def index
      @pagy, @runs = pagy(:offset, Orchestration::PipelineRun.includes(:pipeline).order(created_at: :desc))
    end
  end
end
