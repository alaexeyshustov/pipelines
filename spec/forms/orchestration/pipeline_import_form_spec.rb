require "rails_helper"

RSpec.describe Orchestration::PipelineImportForm do
  let(:result_class) { Struct.new(:pipelines, :errors) }
  let(:pipeline) { build_stubbed(:orchestration_pipeline) }
  let(:importer) do
    result = result_class.new([ pipeline ], [])
    stub_const("FakePipelineImporter", Class.new do
      define_singleton_method(:call) { |hash| (@calls ||= []) << hash; result }
      define_singleton_method(:calls) { @calls }
    end)
  end

  before { stub_const("Orchestration::PipelineImporter", importer) }

  def upload(content)
    Rack::Test::UploadedFile.new(StringIO.new(content), "application/json", original_filename: "p.json")
  end

  describe "#save" do
    it "imports the parsed JSON and exposes the pipelines" do
      form = described_class.new(file: upload('{"format":"pipeline_export"}'))

      expect(form.save).to be true
      expect(importer.calls).to eq([ { "format" => "pipeline_export" } ])
      expect(form.pipelines).to eq([ pipeline ])
    end

    it "fails when no file is given" do
      form = described_class.new(file: nil)

      expect(form.save).to be false
      expect(form.errors.full_messages).to include("File can't be blank")
    end

    it "fails on invalid JSON without calling the importer" do
      form = described_class.new(file: upload("not json"))

      expect(form.save).to be false
      expect(form.errors.full_messages).to include("File is not valid JSON")
      expect(importer.calls).to be_nil
    end

    it "fails when the JSON is not an object" do
      form = described_class.new(file: upload("[1]"))

      expect(form.save).to be false
      expect(form.errors.full_messages).to include("File is not valid JSON")
    end

    it "copies importer errors onto the form" do
      failed = result_class.new([], [ "Unknown agent keyword: foo" ])
      stub_const("Orchestration::PipelineImporter", Class.new { define_singleton_method(:call) { |_hash| failed } })

      form = described_class.new(file: upload("{}"))

      expect(form.save).to be false
      expect(form.errors.full_messages).to eq([ "Unknown agent keyword: foo" ])
      expect(form.pipelines).to eq([])
    end
  end

  describe "upload validation" do
    before { stub_const("#{described_class}::MAX_BYTES", 10) }

    it "rejects an upload over the size limit with a size error" do
      form = described_class.new(file: upload('{"format":"pipeline_export"}'))

      expect(form.save).to be false
      expect(form.errors.full_messages).to include(a_string_matching(/too large/i))
      expect(importer.calls).to be_nil
    end

    it "does not also report a JSON error for an oversized upload" do
      form = described_class.new(file: upload('{"format":"pipeline_export"}'))
      form.valid?

      expect(form.errors.full_messages).not_to include("File is not valid JSON")
    end

    it "accepts an upload exactly at the size limit" do
      form = described_class.new(file: upload('{"a":1}   '))

      expect(form.save).to be true
    end

    it "reads at most MAX_BYTES + 1 bytes even when the upload reports a smaller size" do
      liar = stub_const("UnderReportingUpload", Class.new do
        def initialize(content) = @io = StringIO.new(content)
        def size = 1
        def read(limit = nil) = @io.read(limit)
        def blank? = false
      end)
      form = described_class.new(file: liar.new('{"format":"pipeline_export","pad":"xxxxxxxxxxxxxxxx"}'))

      expect(form.save).to be false
      expect(form.errors.full_messages).to include("File is not valid JSON")
      expect(importer.calls).to be_nil
    end

    { "a String" => "{\"format\":\"pipeline_export\"}", "a Hash" => { "format" => "x" }, "an Array" => [ 1 ] }.each do |label, value|
      it "rejects #{label} as a file without raising" do
        form = described_class.new(file: value)

        expect(form.save).to be false
        expect(form.errors[:file]).to be_present
        expect(importer.calls).to be_nil
      end
    end
  end
end
