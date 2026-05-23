require "rails_helper"

RSpec.describe Orchestration::UpstreamSchemaIndex do
  let(:pipeline) { create(:orchestration_pipeline, initial_input_schema: { "type" => "object", "properties" => { "date" => { "type" => "string" } } }) }
  let(:step1)    { create(:orchestration_step, pipeline: pipeline, position: 1) }
  let(:step2)    { create(:orchestration_step, pipeline: pipeline, position: 2) }

  let(:agent1) { create(:orchestration_agent, output_schema: { "type" => "object", "properties" => { "result" => { "type" => "string" } } }) }
  let(:action1) { create(:orchestration_action, agent: agent1) }
  let(:sa1) { create(:orchestration_step_action, step: step1, position: 1, output_key: "fetch", action: action1) }

  let(:agent2) { create(:orchestration_agent, output_schema: { "type" => "object", "properties" => { "label" => { "type" => "string" } } }) }
  let(:action2) { create(:orchestration_action, agent: agent2) }
  let(:sa2) { create(:orchestration_step_action, step: step2, position: 1, output_key: "classify", action: action2) }

  describe ".build" do
    before { sa1; sa2 }

    it "returns an UpstreamSchemaIndex instance" do
      expect(described_class.build(pipeline)).to be_a(described_class)
    end
  end

  describe "#schemas_before" do
    subject(:index) { described_class.build(pipeline) }

    before { sa1; sa2 }

    it "returns only _initial for the first step action" do
      schemas = index.schemas_before(sa1)
      expect(schemas.keys).to eq(["_initial"])
      expect(schemas["_initial"]).to eq(pipeline.initial_input_schema)
    end

    it "returns _initial and the first step action output for the second step action" do
      schemas = index.schemas_before(sa2)
      expect(schemas.keys).to contain_exactly("_initial", "fetch")
      expect(schemas["fetch"]).to eq(agent1.output_schema)
    end

    it "returns a fallback for an unknown step action" do
      unknown_sa = build_stubbed(:orchestration_step_action, id: 9999)
      schemas = index.schemas_before(unknown_sa)
      expect(schemas).to eq({ "_initial" => nil })
    end

    context "with multiple step actions in the same step" do
      let(:sa1b) { create(:orchestration_step_action, step: step1, position: 2, output_key: "enrich") }

      before { sa1b }

      it "sa1b sees only _initial and fetch before it" do
        schemas = index.schemas_before(sa1b)
        expect(schemas.keys).to contain_exactly("_initial", "fetch")
      end

      it "sa2 sees _initial, fetch, and enrich before it" do
        schemas = index.schemas_before(sa2)
        expect(schemas.keys).to contain_exactly("_initial", "fetch", "enrich")
      end
    end
  end
end
