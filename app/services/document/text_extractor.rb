require "zip"

# Turns a file's bytes into markdown text; shared by email attachments and Drive files.
#
#   Document::TextExtractor.call(data: bytes, mime_type: "application/pdf", filename: "cv.pdf")  # => "# CV ..."
#
# PDFs and images go through Mistral OCR (RubyLLM.ocr, key from MISTRAL_API_KEY); docx is read locally from
# word/document.xml; text/plain passes through. A generic application/octet-stream type is
# inferred from the filename (Document::FileType). Anything else raises Unsupported; provider errors propagate.
class Document::TextExtractor
  class Unsupported < StandardError; end

  DOCX = Document::FileType::DOCX
  OCR_MODEL = "mistral-ocr-latest".freeze
  WORD_NS = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

  def self.call(data:, mime_type:, filename:)
    new(data:, mime_type:, filename:).call
  end

  def initialize(data:, mime_type:, filename:)
    @data = data
    @mime_type = Document::FileType.resolve(mime_type, filename)
    @filename = filename
  end

  def call
    raise Unsupported, "Cannot extract text from #{@mime_type.inspect}" unless Document::FileType.supported?(@mime_type)

    case @mime_type
    when "text/plain" then @data.dup.force_encoding(Encoding::UTF_8).scrub
    when DOCX then docx_text
    else ocr_text
    end
  end

  private

  def ocr_text
    attachment = RubyLLM::Attachment.new(StringIO.new(@data), filename: @filename)
    RubyLLM.ocr(attachment, model: OCR_MODEL, provider: :mistral, assume_model_exists: true).markdown
  end

  def docx_text
    xml = nil
    Zip::File.open_buffer(StringIO.new(@data)) { |zip| xml = zip.read("word/document.xml") }
    Nokogiri::XML(xml).xpath("//w:p", WORD_NS).map { |p| p.xpath(".//w:t", WORD_NS).map(&:text).join }.reject(&:empty?).join("\n\n")
  rescue Zip::Error, Errno::ENOENT => error
    raise Unsupported, "Unreadable docx: #{error.message}"
  end
end
