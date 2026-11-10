require "rails_helper"

RSpec.describe Document::TextExtractor do
  def stub_ocr(pages: [ { "index" => 0, "markdown" => "# Page one" }, { "index" => 1, "markdown" => "Page two" } ])
    stub_request(:post, "https://api.mistral.ai/v1/ocr").to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { model: "mistral-ocr-latest", pages: pages }.to_json
    )
  end

  def docx(paragraphs)
    body = paragraphs.map { |t| "<w:p><w:r><w:t>#{t}</w:t></w:r></w:p>" }.join
    xml = %(<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>#{body}</w:body></w:document>)
    Zip::OutputStream.write_buffer { |zip| zip.put_next_entry("word/document.xml"); zip.write(xml) }.string
  end

  it "OCRs a pdf as a document_url data URL and joins the page markdown" do
    stub = stub_ocr
    text = described_class.call(data: "%PDF-1.4", mime_type: "application/pdf", filename: "cv.pdf")

    expect(text).to eq("# Page one\n\nPage two")
    expect(stub.with { |r|
      body = JSON.parse(r.body)
      body["model"] == "mistral-ocr-latest" && body.dig("document", "type") == "document_url" &&
        body.dig("document", "document_url").start_with?("data:application/pdf;base64,")
    }).to have_been_requested
  end

  it "OCRs an image as an image_url" do
    stub = stub_ocr(pages: [ { "index" => 0, "markdown" => "scan" } ])
    text = described_class.call(data: "\x89PNG".b, mime_type: "image/png", filename: "scan.png")

    expect(text).to eq("scan")
    expect(stub.with { |r| JSON.parse(r.body).dig("document", "type") == "image_url" }).to have_been_requested
  end

  it "extracts docx paragraphs locally without calling OCR" do
    text = described_class.call(data: docx([ "Hello", "World &amp; co" ]), filename: "a.docx",
                                mime_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")

    expect(text).to eq("Hello\n\nWorld & co")
    expect(WebMock).not_to have_requested(:post, "https://api.mistral.ai/v1/ocr")
  end

  it "passes text/plain through" do
    expect(described_class.call(data: "just text", mime_type: "text/plain", filename: "n.txt")).to eq("just text")
  end

  it "raises Unsupported for other types" do
    expect { described_class.call(data: "x", mime_type: "application/zip", filename: "a.zip") }
      .to raise_error(Document::TextExtractor::Unsupported)
  end

  it "infers a generic application/octet-stream type from the filename" do
    stub_ocr(pages: [ { "index" => 0, "markdown" => "scan" } ])

    expect(described_class.call(data: "%PDF-1.4", mime_type: "application/octet-stream", filename: "cv.pdf")).to eq("scan")
    expect(described_class.call(data: docx([ "Hello" ]), mime_type: "application/octet-stream", filename: "a.docx")).to eq("Hello")
  end

  it "stays unsupported when a generic type has no recognisable extension" do
    expect { described_class.call(data: "x", mime_type: "application/octet-stream", filename: "blob") }
      .to raise_error(Document::TextExtractor::Unsupported)
  end

  it "does not send unsupported image formats (svg, heic) to OCR" do
    stub = stub_ocr
    expect { described_class.call(data: "<svg/>", mime_type: "image/svg+xml", filename: "a.svg") }
      .to raise_error(Document::TextExtractor::Unsupported)
    expect(stub).not_to have_been_requested
  end

  it "OCRs every raster format Mistral accepts" do
    stub_ocr
    types = %w[image/png image/jpeg image/webp image/gif image/avif image/bmp image/tiff]
    expect(types.map { |type| described_class.call(data: "x", mime_type: type, filename: "a") }).to all(eq("# Page one\n\nPage two"))
  end

  it "refuses files above the OCR size limit without calling OCR" do
    stub = stub_ocr
    stub_const("#{described_class}::MAX_OCR_BYTES", 4)
    expect { described_class.call(data: "%PDF-1.4", mime_type: "application/pdf", filename: "big.pdf") }
      .to raise_error(Document::TextExtractor::Unsupported, /too large/)
    expect(stub).not_to have_been_requested
  end

  it "refuses a docx whose word/document.xml declares a size above the limit" do
    stub_const("#{described_class}::MAX_DOCX_XML_BYTES", 10)
    expect { described_class.call(data: docx([ "Hello World, long enough" ]), mime_type: described_class::DOCX, filename: "a.docx") }
      .to raise_error(Document::TextExtractor::Unsupported, /too large/)
  end

  it "separates text across line breaks, tabs and paragraphs in docx" do
    xml = %(<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>) +
          %(<w:p><w:r><w:t>One</w:t><w:br/><w:t>Two</w:t><w:tab/><w:t>Three</w:t></w:r></w:p><w:p><w:r><w:t>Four</w:t></w:r></w:p></w:body></w:document>)
    data = Zip::OutputStream.write_buffer { |zip| zip.put_next_entry("word/document.xml"); zip.write(xml) }.string

    expect(described_class.call(data:, mime_type: described_class::DOCX, filename: "a.docx")).to eq("One\nTwo\tThree\n\nFour")
  end
end
