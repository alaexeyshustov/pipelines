# Embeds one Document for vector search (ADR 0014). Idempotent: unchanged text is skipped by digest, so it can be enqueued
# after every store or update. RubyLLM already retries HTTP-level failures, so an unreachable model server gets one outer retry.
class Document::EmbedJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on Faraday::ConnectionFailed, Faraday::TimeoutError, wait: :polynomially_longer, attempts: 2 do |job, error|
    Rails.logger.error("[Document::EmbedJob] document #{job.arguments.first} not embedded after retries: #{error.message}")
  end

  def perform(document_id)
    Embeddings::Embed.call([ Document.find(document_id) ])
    Document::DetectDuplicatesJob.perform_later(document_id)
  end
end
