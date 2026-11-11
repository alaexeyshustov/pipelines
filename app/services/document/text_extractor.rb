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
  DOCX_XML = "word/document.xml".freeze
  WHITESPACE_NODES = { "br" => "\n", "tab" => "\t" }.freeze
  MAX_OCR_BYTES = 20 * 1024 * 1024
  MAX_DOCX_XML_BYTES = 20 * 1024 * 1024
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
    raise Unsupported, "File too large to OCR (#{@data.bytesize} bytes)" if @data.bytesize > MAX_OCR_BYTES

    attachment = RubyLLM::Attachment.new(StringIO.new(@data), filename: @filename)
    RubyLLM.ocr(attachment, model: OCR_MODEL, provider: :mistral, assume_model_exists: true).markdown
  end

  def docx_text
    Nokogiri::XML(docx_xml).xpath("//w:p", WORD_NS).map { |paragraph| paragraph_text(paragraph) }.reject(&:empty?).join("\n\n")
  rescue Zip::Error, Errno::ENOENT => error
    raise Unsupported, "Unreadable docx: #{error.message}"
  end

  def docx_xml
    xml = "" # : String
    Zip::File.open_buffer(StringIO.new(@data)) do |zip|
      entry = zip.find_entry(DOCX_XML) # steep:ignore
      raise Unsupported, "Unreadable docx: no #{DOCX_XML}" unless entry
      raise Unsupported, "docx text too large (#{entry.size} bytes)" if entry.size > MAX_DOCX_XML_BYTES # steep:ignore

      xml = entry.get_input_stream.read.to_s # steep:ignore
    end
    xml
  end

  # Text runs in document order, with <w:br/> as a newline and <w:tab/> as a tab.
  def paragraph_text(paragraph)
    paragraph.xpath(".//w:t | .//w:br | .//w:tab", WORD_NS).map do |node|
      WHITESPACE_NODES.fetch(node.name) { node.text }
    end.join
  end
end
