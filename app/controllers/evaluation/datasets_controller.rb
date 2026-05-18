# frozen_string_literal: true

module Evaluation
  class DatasetsController < ApplicationController
    def generate
      SyntheticDatasetJob.perform_later(
        draft_token:  params[:draft_token],
        agent_name:   params[:agent_name],
        dataset_name: params[:dataset_name],
        count:        params[:count],
        hints:        params[:hints]
      )

      render turbo_stream: turbo_stream.update(
        "dataset-pending",
        html: '<p class="text-xs text-indigo-600">✓ Generation started — this may take a moment.</p>'.html_safe
      )
    rescue StandardError => e
      render turbo_stream: turbo_stream.update(
        "dataset-pending",
        html: "<p class=\"text-xs text-red-600\">Error: #{ERB::Util.html_escape(e.message)}</p>".html_safe
      ), status: :unprocessable_entity
    end
  end
end
