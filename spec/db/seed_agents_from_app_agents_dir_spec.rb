# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260506000001_seed_agents_from_app_agents_dir")

RSpec.describe SeedAgentsFromAppAgentsDir do
  subject(:migration) { described_class.new }

  before { Orchestration::Agent.delete_all }

  describe "#up" do
    before { migration.up }

    it "creates one record per agent file in app/agents/" do
      expect(Orchestration::Agent.count).to eq(7)
    end

    it "creates records with the expected class names" do
      expect(Orchestration::Agent.pluck(:name)).to match_array(%w[
        Emails::ClassifyAgent
        Emails::FilterAgent
        Emails::MappingAgent
        Records::FillAgent
        Records::NormalizeAgent
        Records::ReconcileAgent
        Records::StoreAgent
      ])
    end

    it "is idempotent" do
      expect { migration.up }.not_to change(Orchestration::Agent, :count)
    end

    {
      "Emails::ClassifyAgent"   => { model: "mistral-large-latest", tools: %w[Records::TempFileTool] },
      "Emails::FilterAgent"     => { model: "mistral-large-latest", tools: %w[Records::TempFileTool] },
      "Emails::MappingAgent"    => { model: "mistral-large-latest", tools: %w[Emails::GetTool Records::TempFileTool] },
      "Records::FillAgent"      => { model: "gpt-5.1",              tools: %w[Records::UpdateRowsTool Emails::GetTool] },
      "Records::NormalizeAgent" => { model: "gpt-5.1",              tools: %w[Records::ListRowsTool Records::ReadRowsTool Records::UpdateRowsTool Records::ReadSchemaTool Records::SearchSimilarTool] },
      "Records::ReconcileAgent" => { model: "gpt-5.1",              tools: %w[Records::ReadSchemaTool Records::TempFileTool Records::SearchSimilarTool Records::InsertRowsTool Records::UpdateRowsTool Records::ReadRowsTool] },
      "Records::StoreAgent"     => { model: "mistral-large-latest", tools: %w[Emails::GetLabelsTool Emails::CreateLabelTool Emails::AddLabelsTool Records::InsertRowsTool Records::ReadSchemaTool Emails::GetTool] }
    }.each do |name, config|
      describe name do
        subject(:agent) { Orchestration::Agent.find_by!(name: name) }

        it "has the correct model" do
          expect(agent.model).to eq(config[:model])
        end

        it "has the correct tools" do
          expect(agent.tools).to match_array(config[:tools])
        end

        it "has a prompt set" do
          expect(agent.prompt).to be_present
        end
      end
    end
  end

  describe "#down" do
    before do
      migration.up
      migration.down
    end

    it "removes all seeded agents" do
      expect(Orchestration::Agent.count).to eq(0)
    end
  end
end
