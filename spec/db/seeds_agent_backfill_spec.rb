# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seeds: agent config backfill" do # rubocop:disable RSpec/DescribeClass
  before { load Rails.root.join("db/seeds.rb") }

  {
    "Emails::ClassifyAgent"  => { model: "mistral-large-latest", tools: [ "Records::TempFileTool" ] },
    "Emails::FilterAgent"    => { model: "mistral-large-latest", tools: [ "Records::TempFileTool" ] },
    "Emails::MappingAgent"   => { model: "mistral-large-latest", tools: [ "Emails::GetTool", "Records::TempFileTool" ] },
    "Records::StoreAgent"    => { model: "mistral-large-latest", tools: [ "Emails::GetLabelsTool", "Emails::CreateLabelTool", "Emails::AddLabelsTool",
                                                                           "Records::InsertRowsTool", "Records::ReadSchemaTool", "Emails::GetTool" ] },
    "Records::NormalizeAgent" => { model: "gpt-5.1",            tools: [ "Records::ListRowsTool", "Records::ReadRowsTool", "Records::UpdateRowsTool",
                                                                          "Records::ReadSchemaTool", "Records::SearchSimilarTool" ] },
    "Records::ReconcileAgent" => { model: "gpt-5.1",            tools: [ "Records::ReadSchemaTool", "Records::TempFileTool", "Records::SearchSimilarTool",
                                                                          "Records::InsertRowsTool", "Records::UpdateRowsTool", "Records::ReadRowsTool" ] },
    "Records::FillAgent"      => { model: "gpt-5.1",            tools: [ "Records::UpdateRowsTool", "Emails::GetTool" ] }
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

      it "does not set output_schema (preserves result-wrapper output convention)" do
        expect(agent.output_schema).to be_nil
      end
    end
  end
end
