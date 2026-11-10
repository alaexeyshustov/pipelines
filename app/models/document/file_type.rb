# Which file types Document::TextExtractor can read, and the type of a file whose sender left it generic.
class Document::FileType
  DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze
  # Raster formats the Mistral OCR API accepts as images.
  IMAGES = %w[image/png image/jpeg image/webp image/gif image/avif image/bmp image/tiff].freeze
  GENERIC = [ "application/octet-stream", "binary/octet-stream" ].freeze

  # +mime_type+, or - when it is blank or generic (mail clients and Drive often send application/octet-stream) -
  # the type Marcel infers from the filename's extension, if that says more.
  def self.resolve(mime_type, filename)
    return mime_type unless mime_type.blank? || GENERIC.include?(mime_type)

    inferred = Marcel::MimeType.for(name: filename.to_s)
    GENERIC.include?(inferred) ? mime_type : inferred
  end

  def self.supported?(mime_type)
    [ DOCX, "text/plain", "application/pdf", *IMAGES ].include?(mime_type)
  end
end
