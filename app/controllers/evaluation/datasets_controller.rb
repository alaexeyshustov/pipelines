# frozen_string_literal: true

module Evaluation
  class DatasetsController < ApplicationController
    def generate
      SyntheticDatasetJob.perform_later(**generation_job_params)
      render turbo_stream: turbo_stream.update("dataset-pending", html: generation_started_html)
    rescue StandardError => e
      render turbo_stream: turbo_stream.update("dataset-pending", html: inline_error_html(e.message)),
             status: :unprocessable_content
    end

    def resync
      dataset = Evaluation::Dataset.find(params[:id])
      Evaluation::DatasetSeeder.call(agent_name: dataset.agent_name, sample_size: resync_sample_size)
      render turbo_stream: resync_success_streams(dataset, dataset.dataset_samples.count)
    rescue StandardError => e
      render turbo_stream: resync_error_stream(e), status: :unprocessable_content
    end

    private

    def generation_job_params
      {
        draft_token:  params[:draft_token],
        agent_name:   params[:agent_name],
        dataset_name: params[:dataset_name],
        count:        params[:count],
        hints:        params[:hints]
      }
    end

    def generation_started_html
      '<p class="text-xs text-indigo-600">✓ Generation started — this may take a moment.</p>'.html_safe
    end

    def resync_sample_size
      params[:count]&.to_i || 20
    end

    def resync_error_stream(e)
      turbo_stream.update("dataset-resync-status-#{params[:id]}", html: inline_error_html(e.message))
    end

    def resync_success_streams(dataset, new_count)
      [
        turbo_stream.update("dataset-resync-status-#{dataset.id}",
                            html: '<p class="text-xs text-indigo-600">✓ Resynced.</p>'.html_safe),
        turbo_stream.update("dataset-count-#{dataset.id}", html: "#{new_count} records")
      ]
    end

    # rubocop:disable Rails/OutputSafety
    def inline_error_html(message)
      "<p class=\"text-xs text-red-600\">Error: #{ERB::Util.html_escape(message)}</p>".html_safe
    end
    # rubocop:enable Rails/OutputSafety
  end
end
