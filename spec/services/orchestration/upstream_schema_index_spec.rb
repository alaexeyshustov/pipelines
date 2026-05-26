require "rails_helper"

RSpec.describe Orchestration::UpstreamSchemaIndex do
  let(:pipeline) { create(:orchestration_pipeline, initial_input_schema: { "type" => "object", "properties" => { "date" => { "type" => "string" } } }) }
  let(:first_step) { create(:orchestration_step, pipeline: pipeline, position: 1) }
  let(:fetch_agent) { create(:orchestration_agent, output_schema: { "type" => "object", "properties" => { "result" => { "type" => "string" } } }) }
  let(:fetch_step_action) { create(:orchestration_step_action, step: first_step, position: 1, output_key: "fetch", action: create(:orchestration_action, agent: fetch_agent)) }
  let(:classify_step_action) do
    create(:orchestration_step_action,
           step: create(:orchestration_step, pipeline: pipeline, position: 2),
           position: 1,
           output_key: "classify",
           action: create(:orchestration_action,
                          agent: create(:orchestration_agent,
                                        output_schema: { "type" => "object", "properties" => { "label" => { "type" => "string" } } })))
  end

  describe ".build" do
    before { fetch_step_action; classify_step_action }

    it "returns an UpstreamSchemaIndex instance" do
      expect(described_class.build(pipeline)).to be_a(described_class)
    end
  end

  describe "#schemas_before" do
    subject(:index) { described_class.build(pipeline) }

    before { fetch_step_action; classify_step_action }

    it "returns only _initial for the first step action" do
      schemas = index.schemas_before(fetch_step_action)
      expect(schemas.keys).to eq([ "_initial" ])
      expect(schemas["_initial"]).to eq(pipeline.initial_input_schema)
    end

    it "returns _initial and the first step action output for the second step action" do
      schemas = index.schemas_before(classify_step_action)
      expect(schemas.keys).to contain_exactly("_initial", "fetch")
      expect(schemas["fetch"]).to eq(fetch_agent.output_schema)
    end

    it "returns an empty hash for an unknown step action" do
      unknown_sa = build_stubbed(:orchestration_step_action, id: 9999)
      schemas = index.schemas_before(unknown_sa)
      expect(schemas).to eq({})
    end

    context "with multiple step actions in the same step" do
      let(:enrich_step_action) { create(:orchestration_step_action, step: first_step, position: 2, output_key: "enrich") }

      before { enrich_step_action }

      it "enrich_step_action sees only _initial and fetch before it" do
        schemas = index.schemas_before(enrich_step_action)
        expect(schemas.keys).to contain_exactly("_initial", "fetch")
      end

      it "classify_step_action sees _initial, fetch, and enrich before it" do
        schemas = index.schemas_before(classify_step_action)
        expect(schemas.keys).to contain_exactly("_initial", "fetch", "enrich")
      end
    end
  end
end
