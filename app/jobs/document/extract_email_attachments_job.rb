# Turns the supported attachments (pdf, docx, images, text) of a tagged Gmail email into tagged Documents.
#
# Untagged emails and providers without attachment listing (Yahoo/IMAP) are skipped. Documents dedupe on the
# SHA256 of the bytes, so the same attachment on two emails yields one Document (linked to the first email,
# classified once). A failing attachment is logged and does not block the email's other attachments.
# Orchestrates services here because services must not call each other (App/ServiceMustNotCallService).
class Document::ExtractEmailAttachmentsJob < ApplicationJob
  def perform(email_id)
    email = Email.find(email_id)
    return unless eligible?(email)

    Emails.attachments(email.provider, email.provider_message_id).each do |attachment|
      next unless Document::TextExtractor.supported?(attachment[:mime_type])

      process(email, attachment)
    rescue StandardError => error
      Rails.logger.error("Attachment #{attachment[:filename].inspect} of email #{email.id} failed: #{error.class}: #{error.message}")
    end
  end

  private

  def eligible?(email)
    email.provider == "gmail" && email.taggings.exists?
  end

  def process(email, attachment)
    data = Emails.attachment(email.provider, email.provider_message_id, attachment[:id])
    text = Document::TextExtractor.call(data:, mime_type: attachment[:mime_type], filename: attachment[:filename])
    document = ingest(email, attachment, data, text)
    Tags::Classifier.call(document) if document.previously_new_record?
  end

  def ingest(email, attachment, data, text)
    Document.ingest!(
      title: attachment[:filename], mime_type: attachment[:mime_type], text:, checksum: Digest::SHA256.hexdigest(data),
      source: "email_attachment", source_url: email.source_url, email_id: email.id,
      source_ref: source_ref(email, attachment)
    )
  end

  def source_ref(email, attachment)
    { provider: email.provider, message_id: email.provider_message_id, attachment_id: attachment[:id] }
  end
end
