# frozen_string_literal: true

module Evaluation
  class DatasetsController < ApplicationController
    # TODO: swtich to DatasetSeeder
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

    def resync
      dataset = Evaluation::Dataset.find(params[:id])

      SyntheticDatasetJob.perform_now(
        draft_token: params[:draft_token],
        agent_name:  params[:agent_name],
        dataset_id:  dataset.id,
        count:       params[:count]
      )

      new_count = dataset.dataset_samples.count
      render turbo_stream: [
        turbo_stream.update(
          "dataset-resync-status-#{dataset.id}",
          html: '<p class="text-xs text-indigo-600">✓ Resynced.</p>'.html_safe
        ),
        turbo_stream.update(
          "dataset-count-#{dataset.id}",
          html: "#{new_count} records"
        )
      ]
    rescue StandardError => e
      render turbo_stream: turbo_stream.update(
        "dataset-resync-status-#{params[:id]}",
        html: "<p class=\"text-xs text-red-600\">Error: #{ERB::Util.html_escape(e.message)}</p>".html_safe
      ), status: :unprocessable_entity
    end
  end
end
