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
      result = described_class.call(ids: [ acme.id ]).csv
      expect(result).to be_a(String)
    end

    it "includes COLUMN_NAMES as the header row" do
      result = described_class.call(ids: [ acme.id ]).csv
      headers = CSV.parse(result, headers: true).headers
      expect(headers).to eq(Interview::COLUMN_NAMES.without("id"))
    end

    it "exports only the requested ids" do
      result = described_class.call(ids: [ acme.id ]).csv
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(1)
      expect(rows.first["company"]).to eq("Acme")
    end

    it "exports multiple selected records ordered by applied_at desc" do
      result = described_class.call(ids: [ beta.id, acme.id ]).csv
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(2)
      expect(rows.pluck("company")).to eq(%w[Beta Acme])
    end

    it "exports all records when ids is nil" do
      result = described_class.call(ids: nil).csv
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(2)
      expect(rows.pluck("company")).to eq(%w[Beta Acme])
    end

    it "exports all records when ids is empty" do
      result = described_class.call(ids: []).csv
      rows = CSV.parse(result, headers: true)
      expect(rows.size).to eq(2)
    end

    it "includes all column values for a record" do
      result = described_class.call(ids: [ acme.id ]).csv
      row = CSV.parse(result, headers: true).first
      expect(row.to_h).to include("company" => "Acme", "job_title" => "Backend")
      expect(row["status"]).to eq("pending_reply")
      expect(row["applied_at"]).to eq("2026-01-10")
    end

    it "handles nil date columns as empty strings" do
      result = described_class.call(ids: [ acme.id ]).csv
      row = CSV.parse(result, headers: true).first
      expect(row["rejected_at"]).to be_nil
      expect(row["first_interview_at"]).to be_nil
    end

    describe "formula sanitising" do
      def exported_row(**attrs)
        interview = create(:interview, **attrs)
        CSV.parse(described_class.call(ids: [ interview.id ]).csv, headers: true).first
      end

      [ "=", "+", "-", "@", "\t", "\r" ].each do |char|
        it "prefixes company and job_title starting with #{char.inspect}" do
          row = exported_row(company: "#{char}cmd", job_title: "#{char}title")
          expect(row["company"]).to eq("'#{char}cmd")
          expect(row["job_title"]).to eq("'#{char}title")
        end
      end

      it "leaves values with a trigger character inside unchanged" do
        row = exported_row(company: "A=B", job_title: "Backend")
        expect(row["company"]).to eq("A=B")
        expect(row["job_title"]).to eq("Backend")
      end

      it "leaves nil dates nil and keeps dates as ISO strings" do
        row = exported_row(company: "Acme", applied_at: "2026-01-10")
        expect(row["applied_at"]).to eq("2026-01-10")
        expect(row["rejected_at"]).to be_nil
      end

      it "does not sanitise the header row" do
        interview = create(:interview, company: "Acme")
        header = CSV.parse(described_class.call(ids: [ interview.id ]).csv).first
        expect(header).to eq(Interview::COLUMN_NAMES.without("id"))
      end
    end
  end
end
