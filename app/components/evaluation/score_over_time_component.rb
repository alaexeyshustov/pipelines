# frozen_string_literal: true

module Evaluation
  class ScoreOverTimeComponent < ViewComponent::Base
    def initialize(agent_name:, data:)
      @agent_name = agent_name
      @data = data
    end

    def chart_data_json
      @data.to_json
    end

    def has_data?
      @data.any?
    end
  end
end
