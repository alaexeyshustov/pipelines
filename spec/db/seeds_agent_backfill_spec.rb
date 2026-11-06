require "rails_helper"

RSpec.describe "Seeds: agent config backfill" do # rubocop:disable RSpec/DescribeClass
  # Seeding is per-record by design; the examples check what it left behind.
  before { Prosopite.pause { load Rails.root.join("db/seeds.rb") } }

  agents_without_output_schema = %w[
    Emails::MappingAgent
    Records::NormalizeAgent
    Records::ReconcileAgent
    Records::FillAgent
  ]

  {
    "Orchestration::Agents::EmailsClassifier"   => { model: "mistral-large-latest", tools: [ "Records::TempFileTool" ] },
    "Orchestration::Agents::RecordsNormalizer" => { model: "gpt-5.1",              tools: [ "Records::ListRowsTool", "Records::ReadRowsTool", "Records::UpdateRowsTool",
                                                                            "Records::ReadSchemaTool", "Records::SearchSimilarTool" ] },
    "Orchestration::Agents::RecordsFiller"      => { model: "gpt-5.1",              tools: [ "Records::UpdateRowsTool", "Emails::GetTool" ] }
  }.each do |agent_name, expected|
    describe agent_name do
      subject(:agent) { Orchestration::Agent.find_by!(name: agent_name) }

      it "has model set to #{expected[:model]}" do
        expect(agent.model).to eq(expected[:model])
      end

      it "has exactly the expected tools" do
        expect(agent.tools).to match_array(expected[:tools])
      end

      it "has prompt set" do
        expect(agent.prompt).to be_present
      end

      if agents_without_output_schema.include?(agent_name)
        it "does not set output_schema (no structured output needed)" do
          expect(agent.output_schema).to be_nil
        end
      end
    end
  end

  describe "Orchestration::Agents::EmailsClassifier" do
    subject(:agent) { Orchestration::Agent.find_by!(name: "Orchestration::Agents::EmailsClassifier") }

    it "has output_schema so Yahoo integer UIDs are reliably returned as strings" do
      expect(agent.output_schema).to be_present
    end

    it "has output_schema with required results array" do
      expect(agent.output_schema).to match(
        hash_including(
          "additionalProperties" => false,
          "required"             => [ "results" ],
          "properties"           => hash_including("results" => hash_including("type" => "array"))
        )
      )
    end
  end

  it "does not seed the legacy Applications Workflow pipeline" do
    expect(Orchestration::Pipeline.find_by(name: "Applications Workflow")).to be_nil
  end
end
