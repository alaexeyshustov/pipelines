
require "rails_helper"

RSpec.describe Records::FillJob do
  let(:mails) { create_list(:application_mail, 2, company: nil, job_title: nil) }
  let(:ids)   { mails.map(&:id) }
  let(:captured_inputs) { [] }

  before do
    inputs = captured_inputs
    stub_const("Orchestration::Agents::RecordsFiller", Class.new do
      define_method(:ask) { |input| inputs << input }
    end)
  end

  it "passes selected records and destination table to FillAgent" do
    described_class.perform_now(ids)

    parsed = JSON.parse(captured_inputs.last)
    expect(parsed["destination_table"]).to eq("application_mails")
    expect(parsed["emails"].pluck("id")).to match_array(ids)
  end

  it_behaves_like 'a records job that ignores missing IDs', 'emails'
end
