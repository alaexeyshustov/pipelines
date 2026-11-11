# Flags near-duplicates of one embedded Document for review (GH #227); enqueued by Document::EmbedJob.
class Document::DetectDuplicatesJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(document_id)
    Document::DetectDuplicates.call(Document.find(document_id))
  end
end
