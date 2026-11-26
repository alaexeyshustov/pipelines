# Turns the supported attachments (pdf, docx, images, text) of one email into Documents: download, SHA256 checksum,
# OCR (Document::TextExtractor), Document.ingest!. The caller decides which emails qualify (the pipeline step takes
# tagged emails of either provider).
#
# Documents dedupe on the checksum of the bytes, so the same attachment on two emails yields one Document (linked to
# the first email); the checksum is looked up before the text extraction, so a recurring attachment is never OCR'd
# again, and the existing Document's id is still returned. Unsupported types are ignored silently. A failing
# attachment is returned in +failed+ ("<filename>: <ErrorClass>: <message>") and does not block the email's other
# attachments. The new Documents are +pending+; embedding and tagging are the pipeline's next steps.
#
#   Document::IngestEmailAttachments.call(email)  # => Result[document_ids: [12, 13], failed: []]
class Document::IngestEmailAttachments
  Result = Data.define(:document_ids, :failed)

  def self.call(email)
    new(email).call
  end

  def initialize(email)
    @email = email
  end

  def call
    outcomes = supported_attachments.map { |attachment| ingest_one(attachment) }
    Result.new(document_ids: outcomes.filter_map { |id, _error| id }.uniq, failed: outcomes.filter_map { |_id, error| error })
  end

  private

  def supported_attachments
    Emails.attachments(@email.provider, @email.provider_message_id)
          .map { |attachment| with_resolved_type(attachment) }
          .select { |attachment| Document::FileType.supported?(attachment[:mime_type]) }
  end

  # [document id, nil] or [nil, "<filename>: <ErrorClass>: <message>"]
  def ingest_one(attachment)
    Orchestration::Heartbeat.beat
    [ document_id(attachment), nil ]
  rescue StandardError => error
    Rails.logger.error("Attachment #{attachment[:filename].inspect} of email #{@email.id} failed: #{error.class}: #{error.message}")
    [ nil, "#{attachment[:filename]}: #{error.class}: #{error.message}" ]
  end

  def with_resolved_type(attachment)
    { id: attachment[:id], filename: attachment[:filename], size: attachment[:size],
      mime_type: Document::FileType.resolve(attachment[:mime_type], attachment[:filename]) }
  end

  def document_id(attachment)
    data = Emails.attachment(@email.provider, @email.provider_message_id, attachment[:id])
    checksum = Digest::SHA256.hexdigest(data)
    known = Document.find_by(checksum:)
    return known.id if known

    ingest(attachment, checksum, extract_text(data, attachment)).id
  end

  def extract_text(data, attachment)
    Document::TextExtractor.call(data:, mime_type: attachment[:mime_type].to_s, filename: attachment[:filename]).text
  end

  def ingest(attachment, checksum, text)
    Document.ingest!(
      title: attachment[:filename], mime_type: attachment[:mime_type], text:, checksum:,
      source: Document::EMAIL_ATTACHMENT, source_url: @email.source_url, email_id: @email.id,
      source_ref: { provider: @email.provider, message_id: @email.provider_message_id, attachment_id: attachment[:id] }
    )
  end
end
