# frozen_string_literal: true

module Orchestration
  class RunDetailCardComponent < ViewComponent::Base
    include ActionView::Helpers::DateHelper

    def initialize(run:)
      @run = run
    end

    def formatted_started_at
      @run.started_at&.strftime("%Y-%m-%d %H:%M:%S") || "—"
    end

    def formatted_finished_at
      @run.finished_at&.strftime("%Y-%m-%d %H:%M:%S") || "—"
    end

    def duration
      return "—" unless @run.started_at && @run.finished_at

      distance_of_time_in_words(@run.started_at, @run.finished_at)
    end
  end
end
