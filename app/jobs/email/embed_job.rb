# Embeds one Email for vector search (ADR 0014). The Email Ingestion pipeline embeds in its own step (EmailsEmbed, ADR 0018);
# this job is for embedding a single email on demand (re-embedding, #335). Idempotent: unchanged text is skipped by digest, so it can be enqueued
# after every store or update. RubyLLM already retries HTTP-level failures, so an unreachable model server gets one outer retry.
class Email::EmbedJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on RubyLLM::ConnectionError, wait: :polynomially_longer, attempts: 2 do |job, error|
    Rails.logger.error("[Email::EmbedJob] email #{job.arguments.first} not embedded after retries: #{error.message}")
  end

  def perform(email_id)
    Embeddings::Embed.call([ Email.find(email_id) ])
  end
end
