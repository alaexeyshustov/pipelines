# Full scan of the whitelisted Google Drive folders (Setting "drive_folder_ids": ids or folder URLs separated by
# commas/whitespace, scanned recursively). Each supported file becomes a tagged Document keyed by
# source_ref["drive_file_id"]; Google Docs are exported as docx. Returns a summary of counts.
#
# Document#checksum is always the SHA256 of the bytes (like email attachments), so the same file from email and Drive
# is one Document. Drive's md5Checksum is kept in source_ref["md5"] only to detect changes: a file is unchanged (not
# fetched, extracted or tagged again) when its md5 matches source_ref["md5"] or, for Google Docs which have no md5,
# when modifiedTime matches. If the bytes of a new Drive file already exist as a Document from another source, that
# Document is kept as is (no OCR, no second Document); the Drive file has no Document of its own, so it is downloaded
# again on each scan (cheap) but never re-extracted. Documents of Drive files that no longer appear in the scan are
# deleted; a failed scan raises before anything is deleted, and a failing file is logged and keeps its Document.
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
    @summary ||= { "created" => 0, "updated" => 0, "unchanged" => 0, "deleted" => 0, "failed" => 0 }
  end

  def sync_all(fetcher, folder_ids)
    entries = fetcher.scan(folder_ids)
    existing = Document.where(source: "drive").index_by { |document| document.source_ref["drive_file_id"] }

    entries.each { |entry| sync(fetcher, entry, existing[entry.id]) }
    delete_missing(existing, entries)
  end

  def sync(fetcher, entry, document)
    return unless Document::TextExtractor.supported?(mime_type_of(entry))

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
    entry.mime_type == Emails::Adapters::DriveFileFetcher::GOOGLE_DOC_MIME ? Document::TextExtractor::DOCX : entry.mime_type
  end

  def unchanged?(entry, document)
    if entry.md5
      document.source_ref["md5"] == entry.md5
    else
      document.source_ref["modified_time"] == entry.modified_time
    end
  end

  def process(fetcher, entry, document)
    file = fetcher.fetch(entry.id)
    checksum = Digest::SHA256.hexdigest(file.data)
    return if document.nil? && Document.exists?(checksum:)

    text = Document::TextExtractor.call(data: file.data, mime_type: file.mime_type, filename: entry.name)
    document = store(attributes_for(entry, file, text, checksum), document)
    Tags::Classifier.call(document) if document
  end

  # The changed or newly created Document, or nil when identical content already exists as another Document.
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
    document
  end

  def attributes_for(entry, file, text, checksum)
    {
      title: entry.name, mime_type: file.mime_type, text:, checksum:,
      source: "drive", source_url: entry.web_view_link,
      source_ref: { provider: "drive", drive_file_id: entry.id, md5: entry.md5, modified_time: entry.modified_time }
    }
  end

  def delete_missing(existing, entries)
    present = entries.to_set(&:id)
    existing.each do |drive_file_id, document|
      next if present.include?(drive_file_id)

      document.destroy!
      summary["deleted"] += 1
    end
  end
end
