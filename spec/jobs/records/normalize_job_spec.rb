# frozen_string_literal: true

require "rails_helper"

RSpec.describe Records::NormalizeJob do
  let(:mails) { create_list(:application_mail, 2) }
  let(:ids)   { mails.map(&:id) }
  let(:agent) { instance_double(Records::NormalizeAgent) }

  before do
    allow(Records::NormalizeAgent).to receive(:new).and_return(agent)
    allow(agent).to receive(:ask).and_return(double(content: '{"rows_updated":2}'))
  end

  it "passes selected records, destination table and columns to NormalizeAgent" do
    described_class.perform_now(ids)

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed).to include(
        "destination_table" => "application_mails",
        "columns_to_normalize" => %w[company job_title]
      )
      expect(parsed["records_to_normalize"].map { |r| r["id"] }).to match_array(ids)
    end
  end

  it "ignores IDs not in the database" do
    described_class.perform_now([ 0 ])

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed["records_to_normalize"]).to be_empty
    end
  end
end
