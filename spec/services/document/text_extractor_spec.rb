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

  it "reports supported types" do
    expect(described_class.supported?("image/jpeg")).to be(true)
    expect(described_class.supported?("application/zip")).to be(false)
  end
end
