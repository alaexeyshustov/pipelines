# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::Improvement::LoadSchemaTool do
  subject(:tool) { described_class.new }

  describe "#execute" do
    it "returns the output_schema when the agent exists" do
      schema = { "type" => "object", "properties" => { "label" => { "type" => "string" } } }
      create(:orchestration_agent, name: "Emails::ClassifyAgent", output_schema: schema)

      expect(tool.execute("Emails::ClassifyAgent")).to eq(schema)
    end

    it "returns nil when the agent does not exist" do
      expect(tool.execute("NonExistentAgent")).to be_nil
    end
  end
end
