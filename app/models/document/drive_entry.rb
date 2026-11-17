# A Drive file listed by a scan, as the Document it maps to: its type, whether its Document is current, and the
# attributes to store.
class Document::DriveEntry
  attr_reader :entry

  def initialize(entry)
    @entry = entry
  end

  def supported?
    Document::FileType.supported?(mime_type)
  end

  # Google Docs are exported as docx.
  def mime_type
    return Document::FileType::DOCX if entry.mime_type == Emails::Adapters::DriveFileFetcher::GOOGLE_DOC_MIME

    Document::FileType.resolve(entry.mime_type, entry.name)
  end

  # Drive's md5 when it has one; Google Docs have none, so their modifiedTime.
  def unchanged?(document)
    if entry.md5
      document.source_ref["md5"] == entry.md5
    else
      document.source_ref["modified_time"] == entry.modified_time
    end
  end

  def attributes(file, text, checksum)
    {
      title: entry.name, mime_type: Document::FileType.resolve(file.mime_type, entry.name), text:, checksum:,
      source: Document::DRIVE, source_url: entry.web_view_link, tagged_at: nil,
      source_ref:
    }
  end

  def relink_attributes
    { title: entry.name, source_url: entry.web_view_link, source_ref: }
  end

  def source_ref
    { provider: Document::DRIVE_REF_PROVIDER, drive_file_id: entry.id, md5: entry.md5, modified_time: entry.modified_time }
  end
end
