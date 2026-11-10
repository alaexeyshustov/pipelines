# Which file types Document::TextExtractor can read, and the type of a file whose sender left it generic.
class Document::FileType
  DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze
  GENERIC = [ "application/octet-stream", "binary/octet-stream" ].freeze

  # +mime_type+, or - when it is blank or generic (mail clients and Drive often send application/octet-stream) -
  # the type Marcel infers from the filename's extension, if that says more.
  def self.resolve(mime_type, filename)
    return mime_type unless mime_type.blank? || GENERIC.include?(mime_type)

    inferred = Marcel::MimeType.for(name: filename.to_s)
    GENERIC.include?(inferred) ? mime_type : inferred
  end

  def self.supported?(mime_type)
    mime_type == DOCX || mime_type == "text/plain" || mime_type == "application/pdf" || mime_type.to_s.start_with?("image/")
  end
end
