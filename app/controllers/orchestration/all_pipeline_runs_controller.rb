# frozen_string_literal: true

module Orchestration
  class AllPipelineRunsController < ApplicationController
    def index
      @pagy, @runs = pagy(:offset, Orchestration::PipelineRun.includes(:pipeline).recent_first)
    end
  end
end
