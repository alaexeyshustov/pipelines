require "rails_helper"

RSpec.describe "Orchestration pipeline export/import" do
  let(:envelope_for) { ->(pipelines) { { "format" => "pipeline_export", "schema_version" => 1, "pipelines" => pipelines.map(&:name) } } }
  let(:exporter) do
    envelope = envelope_for
    Class.new { define_singleton_method(:call) { |pipelines| envelope.call(Array(pipelines)) } }
  end

  before { stub_const("Orchestration::PipelineExporter", exporter) }

  describe "GET /orchestration/pipelines/:id/export" do
    it "downloads the pipeline as JSON" do
      pipeline = create(:orchestration_pipeline, name: "My Pipeline")

      get export_orchestration_pipeline_path(pipeline)

      expect(response.headers["Content-Disposition"]).to include('filename="pipeline-my-pipeline.json"')
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["pipelines"]).to eq([ "My Pipeline" ])
    end
  end

  describe "GET /orchestration/pipelines/export_all" do
    it "downloads all pipelines in one file" do
      create(:orchestration_pipeline, name: "A")
      create(:orchestration_pipeline, name: "B")

      get export_all_orchestration_pipelines_path

      expect(response.headers["Content-Disposition"]).to include('filename="pipelines.json"')
      expect(response.parsed_body["pipelines"]).to contain_exactly("A", "B")
    end
  end

  describe "POST /orchestration/pipeline_imports" do
    let(:result_class) { Struct.new(:pipelines, :errors) }
    let(:file) do
      Rack::Test::UploadedFile.new(StringIO.new('{"format":"pipeline_export"}'), "application/json", original_filename: "p.json")
    end

    it "redirects with a notice listing imported pipelines" do
      imported = build_stubbed(:orchestration_pipeline, name: "Imported One")
      result = result_class.new([ imported ], [])
      stub_const("Orchestration::PipelineImporter", Class.new { define_singleton_method(:call) { |_hash| result } })

      post orchestration_pipeline_imports_path, params: { file: file }

      expect(response).to redirect_to(orchestration_pipelines_path)
      expect(flash[:notice]).to include("Imported One")
    end

    it "redirects with an alert when the importer reports errors" do
      result = result_class.new([], [ "Unknown agent keyword: x" ])
      stub_const("Orchestration::PipelineImporter", Class.new { define_singleton_method(:call) { |_hash| result } })

      post orchestration_pipeline_imports_path, params: { file: file }

      expect(response).to redirect_to(orchestration_pipelines_path)
      expect(flash[:alert]).to include("Unknown agent keyword: x")
    end

    it "redirects with an alert when no file is given" do
      post orchestration_pipeline_imports_path

      expect(response).to redirect_to(orchestration_pipelines_path)
      expect(flash[:alert]).to include("File can't be blank")
    end
  end

  describe "UI" do
    it "shows Export all and Import on the index page" do
      get orchestration_pipelines_path

      expect(response.body).to include(export_all_orchestration_pipelines_path)
      expect(response.body).to include(orchestration_pipeline_imports_path)
    end

    it "shows Export on the show page" do
      pipeline = create(:orchestration_pipeline)

      get orchestration_pipeline_path(pipeline)

      expect(response.body).to include(export_orchestration_pipeline_path(pipeline))
    end
  end
end
