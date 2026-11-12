# Fetches a Document's original file live from its source (Gmail attachment or Drive file) via +source_ref+.
#
#   file = Document::Download.call(document)  # => File(data:, filename:, mime_type:)
class Document::Download
  File = Data.define(:data, :filename, :mime_type)

  class Unsupported < StandardError; end

  def self.call(document)
    new(document).call
  end

  def initialize(document)
    @document = document
  end

  def call
    ref = @document.source_ref
    case ref["provider"]
    when Emails::GMAIL then from_gmail(ref)
    when Document::DRIVE_REF_PROVIDER then from_drive(ref)
    else raise Unsupported, "Cannot download from #{ref['provider'].inspect}"
    end
  end

  private

  def from_gmail(ref)
    data = Emails.attachment(Emails::GMAIL, ref.fetch("message_id").to_s, ref.fetch("attachment_id").to_s)
    File.new(data:, filename: filename(@document.title, @document.mime_type), mime_type: @document.mime_type)
  end

  def from_drive(ref)
    file = Emails::Adapters::DriveFileFetcher.from_env.fetch(ref.fetch("drive_file_id").to_s)
    File.new(data: file.data, filename: filename(file.filename, file.mime_type), mime_type: file.mime_type)
  end

  def filename(name, mime_type)
    return name unless ::File.extname(name).empty?

    extension = Rack::Mime::MIME_TYPES.key(mime_type.to_s)
    "#{name}#{extension}"
  end
end
