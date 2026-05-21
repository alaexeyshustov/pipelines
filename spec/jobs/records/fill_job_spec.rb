# frozen_string_literal: true

require "rails_helper"

RSpec.describe Records::FillJob do
  let(:mails) { create_list(:application_mail, 2, company: nil, job_title: nil) }
  let(:ids)   { mails.map(&:id) }
  let(:agent) { instance_double(Records::FillAgent) }

  before do
    allow(Records::FillAgent).to receive(:new).and_return(agent)
    allow(agent).to receive(:ask).and_return(double(content: '{"rows_updated":2}'))
  end

  it "passes selected records and destination table to FillAgent" do
    described_class.perform_now(ids)

    expect(agent).to have_received(:ask) do |input|
      parsed = JSON.parse(input)
      expect(parsed["destination_table"]).to eq("application_mails")
      expect(parsed["emails"].map { |e| e["id"] }).to match_array(ids)
    end
  end

  it_behaves_like 'a records job that ignores missing IDs', 'emails'
end
