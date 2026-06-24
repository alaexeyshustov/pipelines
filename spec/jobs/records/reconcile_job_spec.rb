# frozen_string_literal: true

require "rails_helper"

RSpec.describe Records::ReconcileJob do
  let(:mails) { create_list(:application_mail, 2, company: "Acme", job_title: "Engineer") }
  let(:ids)   { mails.map(&:id) }
  let(:captured_inputs) { [] }

  before do
    inputs = captured_inputs
    stub_const("Orchestration::Agents::RecordsReconciler", Class.new do
      define_method(:ask) { |input| inputs << input }
    end)
  end

  it "passes selected mails and destination table to ReconcileAgent" do
    described_class.perform_now(ids)

    parsed = JSON.parse(captured_inputs.last)
    expect(parsed["destination_table"]).to eq("interviews")
    expect(parsed["emailsto_reconcile"].pluck("id")).to match_array(ids)
  end

  it "includes matching_columns, statuses and initial_status in input" do
    described_class.perform_now(ids)

    parsed = JSON.parse(captured_inputs.last)
    expect(parsed).to include(
      "matching_columns" => %w[company job_title],
      "initial_status" => Interview::STATUSES.first
    )
    expect(parsed["statuses"]).to eq(Interview::STATUSES)
  end

  it_behaves_like 'a records job that ignores missing IDs', 'emailsto_reconcile'
end
