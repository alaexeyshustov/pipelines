# frozen_string_literal: true

require "rails_helper"

RSpec.describe Interviews::CsvExportService do
  describe "#call" do
    let!(:acme) do
      create(:interview, company: "Acme", job_title: "Backend",
             status: "pending_reply", applied_at: "2026-01-10")
    end
    let!(:beta) do
      create(:interview, company: "Beta", job_title: "Frontend",
             status: "having_interviews", applied_at: "2026-02-05")
    end

    it "returns a CSV string" do
      result = described_class.new(ids: [ acme.id ]).call
      expect(result).to be_a(String)
    end

    it "includes COLUMN_NAMES as the header row" do
      result = described_class.new(ids: [ acme.id ]).call
      headers = CSV.parse(result, headers: true).headers
      expect(headers).to eq(Interview::COLUMN_NAMES.without("id"))
    end

    it "exports only the requested ids" do
      result = described_class.new(ids: [ acme.id ]).call
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(1)
      expect(rows.first["company"]).to eq("Acme")
    end

    it "exports multiple selected records ordered by company then job_title" do
      result = described_class.new(ids: [ beta.id, acme.id ]).call
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r["company"] }).to eq(%w[Acme Beta])
    end

    it "exports all records when ids is nil" do
      result = described_class.new(ids: nil).call
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r["company"] }).to eq(%w[Acme Beta])
    end

    it "exports all records when ids is empty" do
      result = described_class.new(ids: []).call
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(2)
    end

    it "includes all column values for a record" do
      result = described_class.new(ids: [ acme.id ]).call
      row = CSV.parse(result, headers: true).first
      expect(row.to_h).to include("company" => "Acme", "job_title" => "Backend")
      expect(row["status"]).to eq("pending_reply")
      expect(row["applied_at"]).to eq("2026-01-10")
    end

    it "handles nil date columns as empty strings" do
      result = described_class.new(ids: [ acme.id ]).call
      row = CSV.parse(result, headers: true).first
      expect(row["rejected_at"]).to be_nil
      expect(row["first_interview_at"]).to be_nil
    end
  end
end
