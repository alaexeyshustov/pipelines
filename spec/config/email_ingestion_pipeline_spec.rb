require "rails_helper"

RSpec.describe "config/pipelines/email_ingestion.json" do # rubocop:disable RSpec/DescribeClass
  let(:path) { Rails.root.join("config/pipelines/email_ingestion.json") }
  let(:data) { JSON.parse(File.read(path)) }
  let(:definition) { data.fetch("pipelines").sole }
  let(:steps) { definition.fetch("steps") }
  let(:step_actions) { steps.flat_map { |step| step.fetch("step_actions") } }
  let(:imported) { Orchestration::PipelineImporter.call(data) }

  def mapping_of(position) = step_actions.fetch(position - 1).fetch("input_mapping")

  it "is a pipeline export holding one pipeline named Email Ingestion" do
    expect(data).to include("format" => "pipeline_export", "schema_version" => 1)
    expect(definition["name"]).to eq("Email Ingestion")
  end

  it "has no cron, runs on demand" do
    expect(definition["cron_expression"]).to be_nil
  end

  it "has six steps with one service action each, in the ingestion order" do
    expect(step_actions.map { |step_action| step_action.dig("action", "agent_class") }).to eq(
      %w[agent_emails_list agent_emails_classify agent_emails_embed agent_attachments_ingest agent_documents_classify agent_documents_embed]
    )
    expect(steps.map { |step| step["step_actions"].size }).to all(eq(1))
    expect(step_actions.map { |step_action| step_action.dig("action", "kind") }).to all(eq("service"))
  end

  it "declares the initial input: providers (required, at least one of gmail and yahoo) and optional described dates", :aggregate_failures do
    schema = definition.fetch("initial_input_schema")

    expect(schema["required"]).to eq([ "providers" ])
    expect(schema.dig("properties", "providers")).to include("type" => "array", "minItems" => 1, "description" => be_present)
    expect(schema.dig("properties", "providers", "items", "enum")).to match_array(%w[gmail yahoo])
    %w[date_from date_to].each do |field|
      expect(schema.dig("properties", field)).to include("type" => "string", "format" => "date", "description" => be_present)
    end
  end

  it "maps step 1 to the initial providers and optional dates" do
    expect(mapping_of(1)).to include(
      "providers" => include("from" => "_initial", "path" => "providers"),
      "date_from" => include("from" => "_initial", "path" => "date_from", "optional" => true),
      "date_to" => include("from" => "_initial", "path" => "date_to", "optional" => true)
    )
  end

  it "feeds steps 2 to 4 the email ids of step 1 and steps 5 and 6 the document ids of step 4", :aggregate_failures do
    list_key = step_actions[0]["output_key"]
    ingest_key = step_actions[3]["output_key"]

    expect(list_key).to eq("list_emails")
    expect(ingest_key).to eq("ingest_attachments")
    [ 2, 3, 4 ].each { |position| expect(mapping_of(position)).to eq("email_ids" => { "from" => list_key, "path" => "email_ids" }) }
    [ 5, 6 ].each { |position| expect(mapping_of(position)).to eq("document_ids" => { "from" => ingest_key, "path" => "document_ids" }) }
  end

  describe "importing" do
    it "succeeds with no errors, creating a disabled pipeline with six steps" do
      expect(imported.errors).to eq([])
      pipeline = imported.pipelines.sole
      expect(pipeline).to have_attributes(name: "Email Ingestion", enabled: false, cron_expression: nil)
      expect(pipeline.steps.count).to eq(6)
    end

    it "passes PipelineValidator with no errors and no warnings" do
      pipeline = imported.pipelines.sole

      results = Orchestration::PipelineValidator.new(pipeline).validate

      expect(results.size).to eq(6)
      expect(results.flat_map(&:errors)).to be_empty
      expect(results.flat_map(&:warnings)).to be_empty
    end

    it "survives a round trip: import, export, import again" do
      exported = Orchestration::PipelineExporter.call(imported.pipelines)
      again = Orchestration::PipelineImporter.call(JSON.parse(JSON.generate(exported)))

      expect(again.errors).to eq([])
      expect(again.pipelines.sole.steps.count).to eq(6)
      expect(exported.fetch("pipelines").sole.except("enabled")).to eq(definition.except("enabled"))
    end
  end
end
