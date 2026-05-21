# frozen_string_literal: true

require "rails_helper"

RSpec.describe Records::NormalizeJob do
  let(:mails) { create_list(:application_mail, 2) }
  let(:ids)   { mails.map(&:id) }
  let(:captured_inputs) { [] }

  before do
    inputs = captured_inputs
    stub_const("Records::NormalizeAgent", Class.new do
      define_method(:ask) { |input| inputs << input }
    end)
  end

  it "passes selected records, destination table and columns to NormalizeAgent" do
    described_class.perform_now(ids)

    parsed = JSON.parse(captured_inputs.last)
    expect(parsed).to include(
      "destination_table" => "application_mails",
      "columns_to_normalize" => %w[company job_title]
    )
    expect(parsed["records_to_normalize"].map { |r| r["id"] }).to match_array(ids)
  end

  it_behaves_like 'a records job that ignores missing IDs', 'records_to_normalize'
end
