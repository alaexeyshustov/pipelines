# frozen_string_literal: true

require "rails_helper"

RSpec.describe Records::ReconcileJob do
  let(:mails) { create_list(:application_mail, 2, company: "Acme", job_title: "Engineer") }
  let(:ids)   { mails.map(&:id) }
  let(:agent) { instance_double(Records::ReconcileAgent) }

  before do
    allow(Records::ReconcileAgent).to receive(:new).and_return(agent)
    allow(agent).to receive(:ask).and_return(double(content: '{"rows_inserted":1,"rows_updated":1}'))
  end

  it "passes selected mails and destination table to ReconcileAgent" do
    described_class.perform_now(ids)

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed["destination_table"]).to eq("interviews")
      expect(parsed["emailsto_reconcile"].map { |e| e["id"] }).to match_array(ids)
    end
  end

  it "includes matching_columns, statuses and initial_status in input" do
    described_class.perform_now(ids)

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed).to include(
        "matching_columns" => %w[company job_title],
        "initial_status" => Interview::STATUSES.first
      )
      expect(parsed["statuses"]).to eq(Interview::STATUSES)
    end
  end

  it "ignores IDs not in the database" do
    described_class.perform_now([ 0 ])

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed["emailsto_reconcile"]).to be_empty
    end
  end
end
