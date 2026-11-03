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
    when "gmail" then from_gmail(ref)
    when "drive" then from_drive(ref)
    else raise Unsupported, "Cannot download from #{ref['provider'].inspect}"
    end
  end

  private

  def from_gmail(ref)
    data = Emails.attachment("gmail", ref.fetch("message_id"), ref.fetch("attachment_id"))
    File.new(data:, filename: filename, mime_type: @document.mime_type)
  end

  def from_drive(ref)
    file = Emails::Adapters::DriveFileFetcher.from_env.fetch(ref.fetch("drive_file_id"))
    File.new(data: file.data, filename: file.filename, mime_type: file.mime_type)
  end

  def filename
    title = @document.title
    return title unless ::File.extname(title).empty?

    extension = Rack::Mime::MIME_TYPES.key(@document.mime_type)
    "#{title}#{extension}"
  end
end
