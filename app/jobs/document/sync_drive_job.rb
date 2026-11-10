# Full scan of the whitelisted Google Drive folders (Setting "drive_folder_ids": ids or folder URLs separated by
# commas/whitespace, scanned recursively). Each supported file becomes a tagged Document keyed by
# source_ref["drive_file_id"]; Google Docs are exported as docx. Returns a summary of counts.
#
# Tagging is not done here: a new or changed Document is queued for embedding and for Document::TagJob, and a
# changed one gets tagged_at cleared so it is tagged again. Tagging that failed leaves tagged_at NULL, so every scan
# also queues Document::TagJob for the Drive Documents still untagged after Document::TagJob::REQUEUE_AFTER ("requeued").
#
# Document#checksum is always the SHA256 of the bytes (like email attachments), so the same file from email and Drive
# is one Document. Drive's md5Checksum is kept in source_ref["md5"] only to detect changes: a file is unchanged (not
# fetched, extracted or tagged again) when its md5 matches source_ref["md5"] or, for Google Docs which have no md5,
# when modifiedTime matches. If the bytes of a new Drive file already exist as a Document from another source, that
# Document is kept as is (no OCR, no second Document); the Drive file has no Document of its own, so it is downloaded
# again on each scan (cheap) but never re-extracted. A changed file whose new bytes equal another Document's gets the
# same treatment: its stale Drive Document is destroyed and the other one kept ("merged"). Documents of Drive files that no longer appear in the scan are
# deleted; a failed scan raises before anything is deleted, and a failing file is logged and keeps its Document.
# Drive answers a revoked or mistyped folder id with an empty listing, not an error, so when any whitelisted folder
# lists nothing at its top level nothing is deleted in that scan ("empty_folders" counts them, and they are logged): the
# Documents are not attributed to a folder (a file can sit under several), so this is the safe, simple rule; the
# price is that deletions wait while a whitelisted folder is genuinely empty.
# An empty whitelist is a no-op. Orchestrates services here because services must not call each other.
class Document::SyncDriveJob < ApplicationJob
  SETTING_KEY = "drive_folder_ids".freeze

  def perform
    folder_ids = self.class.folder_ids
    return summary if folder_ids.empty?

    sync_all(Emails::Adapters::DriveFileFetcher.from_env, folder_ids)
    summary
  end

  def self.folder_ids
    Setting.fetch(SETTING_KEY).to_s.split(/[\s,]+/).filter_map do |value|
      id = value.match(%r{/folders/([^/?#]+)})&.[](1) || value
      id unless id.empty?
    end.uniq
  end

  private

  def summary
    @summary ||= { "created" => 0, "updated" => 0, "unchanged" => 0, "deleted" => 0, "failed" => 0, "requeued" => 0, "empty_folders" => 0, "merged" => 0 }
  end

  def sync_all(fetcher, folder_ids)
    entries = fetcher.scan(folder_ids)
    existing = Document.where(source: Document::DRIVE).index_by { |document| document.source_ref["drive_file_id"] }

    entries.each { |entry| sync(fetcher, entry, existing[entry.id]) }
    delete_missing(existing, entries, fetcher.empty_folders(folder_ids))
    requeue_untagged
  end

  def sync(fetcher, entry, document)
    return unless Document::FileType.supported?(mime_type_of(entry))

    if document && unchanged?(entry, document)
      summary["unchanged"] += 1
    else
      process(fetcher, entry, document)
    end
  rescue StandardError => error
    summary["failed"] += 1
    Rails.logger.error("Drive file #{entry.name.inspect} (#{entry.id}) failed: #{error.class}: #{error.message}")
  end

  def mime_type_of(entry)
    return Document::FileType::DOCX if entry.mime_type == Emails::Adapters::DriveFileFetcher::GOOGLE_DOC_MIME

    Document::FileType.resolve(entry.mime_type, entry.name)
  end

  def unchanged?(entry, document)
    if entry.md5
      document.source_ref["md5"] == entry.md5
    else
      document.source_ref["modified_time"] == entry.modified_time
    end
  end

  def process(fetcher, entry, document)
    file = fetch_file(fetcher, entry)
    checksum = Digest::SHA256.hexdigest(file.data)
    return merge_into_existing(document) if Document.where.not(id: document&.id).exists?(checksum:)

    text = Document::TextExtractor.call(data: file.data, mime_type: file.mime_type, filename: entry.name)
    store(attributes_for(entry, file, text, checksum), document)
  end

  def fetch_file(fetcher, entry)
    fetcher.fetch(entry.id, name: entry.name, mime_type: entry.mime_type)
  end

  # The bytes already exist as another Document, which is kept. A changed file that had a Drive Document of its own
  # loses it (it would break checksum uniqueness), so it is in the same state as a new Drive file with known bytes.
  def merge_into_existing(document)
    return unless document

    document.destroy!
    summary["merged"] += 1
  end

  # Stores the changed or new Document and queues its processing; nothing for identical content that already
  # exists as another Document.
  def store(attributes, document)
    if document
      document.update!(attributes)
      stored(document, "updated")
    else
      created = Document.ingest!(attributes)
      stored(created, "created") if created.previously_new_record?
    end
  end

  def stored(document, outcome)
    summary[outcome] += 1
    Document::EmbedJob.perform_later(document.id)
    queue_tagging(document.id)
  end

  def queue_tagging(document_id)
    queued_tagging << document_id
    Document::TagJob.perform_later(document_id)
  end

  def queued_tagging
    @queued_tagging ||= []
  end

  def attributes_for(entry, file, text, checksum)
    {
      title: entry.name, mime_type: Document::FileType.resolve(file.mime_type, entry.name), text:, checksum:,
      source: Document::DRIVE, source_url: entry.web_view_link, tagged_at: nil,
      source_ref: { provider: Document::DRIVE_REF_PROVIDER, drive_file_id: entry.id, md5: entry.md5, modified_time: entry.modified_time }
    }
  end

  def delete_missing(existing, entries, empty_folder_ids)
    summary["empty_folders"] = empty_folder_ids.size
    return warn_empty(empty_folder_ids) if empty_folder_ids.any?

    present = entries.to_set(&:id)
    existing.each do |drive_file_id, document|
      next if present.include?(drive_file_id)

      document.destroy!
      summary["deleted"] += 1
    end
  end

  def warn_empty(folder_ids)
    Rails.logger.warn("Drive folder(s) #{folder_ids.join(', ')} listed no files; deleting no Documents this scan")
  end

  def requeue_untagged
    stale = Document.awaiting_tagging(before: Document::TagJob::REQUEUE_AFTER.ago).where(source: Document::DRIVE)
                    .where.not(id: queued_tagging).pluck(:id)
    stale.each { |document_id| Document::TagJob.perform_later(document_id) }
    summary["requeued"] = stale.size
  end
end
