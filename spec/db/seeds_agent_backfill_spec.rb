# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seeds: agent config backfill" do # rubocop:disable RSpec/DescribeClass
  before { load Rails.root.join("db/seeds.rb") }

  agents_without_output_schema = %w[
    Emails::MappingAgent
    Records::NormalizeAgent
    Records::ReconcileAgent
    Records::FillAgent
  ]

  {
    "Orchestration::Agents::EmailsClassifier"   => { model: "mistral-large-latest", tools: [ "Records::TempFileTool" ] },
    "Orchestration::Agents::EmailsFilter"     => { model: "mistral-large-latest", tools: [ "Records::TempFileTool" ] },
    "Orchestration::Agents::EmailsMapper"    => { model: "mistral-large-latest", tools: [ "Emails::GetTool", "Records::TempFileTool" ] },
    "Orchestration::Agents::RecordsStorer"     => { model: "mistral-large-latest", tools: [ "Emails::GetLabelsTool", "Emails::CreateLabelTool", "Emails::AddLabelsTool",
                                                                            "Records::InsertRowsTool", "Records::ReadSchemaTool", "Emails::GetTool" ] },
    "Orchestration::Agents::RecordsNormalizer" => { model: "gpt-5.1",              tools: [ "Records::ListRowsTool", "Records::ReadRowsTool", "Records::UpdateRowsTool",
                                                                            "Records::ReadSchemaTool", "Records::SearchSimilarTool" ] },
    "Orchestration::Agents::RecordsReconciler" => { model: "gpt-5.1",              tools: [ "Records::ReadSchemaTool", "Records::TempFileTool", "Records::SearchSimilarTool",
                                                                            "Records::InsertRowsTool", "Records::UpdateRowsTool", "Records::ReadRowsTool" ] },
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

  describe "Orchestration::Agents::EmailsFilter" do
    subject(:agent) { Orchestration::Agent.find_by!(name: "Orchestration::Agents::EmailsFilter") }

    it "has output_schema so Mistral enforces structured output (prevents bare-array deviation)" do
      expect(agent.output_schema).to be_present
    end

    it "has output_schema with required results array (Mistral requirement)" do
      expect(agent.output_schema).to match(
        hash_including(
          "additionalProperties" => false,
          "required"             => [ "results" ],
          "properties"           => hash_including("results" => hash_including("type" => "array"))
        )
      )
    end
  end

  describe "Ingest Emails step" do
    subject(:step_action) { Orchestration::Pipeline.find_by!(name: "Applications Workflow").steps.find_by!(name: "Ingest Emails").step_actions.first! }

    it "uses ids_from: 'results' (Filter Emails output is unwrapped since it has output_schema)" do
      filter_op = step_action.input_mapping["operations"]["value"].find { |op| op["type"] == "filter_by_ids" }
      expect(filter_op["ids_from"]).to eq("results")
    end
  end

  describe "Orchestration::Agents::RecordsStorer" do
    subject(:agent) { Orchestration::Agent.find_by!(name: "Orchestration::Agents::RecordsStorer") }

    it "has output_schema with additionalProperties: false at all object levels (Mistral requirement)" do
      expect(agent.output_schema).to match(
        hash_including(
          "additionalProperties" => false,
          "properties"           => hash_including(
            "result" => hash_including("additionalProperties" => false)
          )
        )
      )
    end

    it "has required fields on the result object (Mistral requirement)" do
      expect(agent.output_schema.dig("properties", "result", "required"))
        .to match_array(%w[rows_inserted ids])
    end
  end
end
