require "rails_helper"

RSpec.describe Orchestration::PipelineImportForm do
  let(:result_class) { Struct.new(:pipelines, :errors) }
  let(:pipeline) { build_stubbed(:orchestration_pipeline) }
  let(:importer) do
    result = result_class.new([ pipeline ], [])
    Class.new do
      define_singleton_method(:call) { |hash| (@calls ||= []) << hash; result }
      define_singleton_method(:calls) { @calls }
    end
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
end
