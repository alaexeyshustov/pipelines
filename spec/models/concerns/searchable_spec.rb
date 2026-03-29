# frozen_string_literal: true

require "rails_helper"

RSpec.describe Searchable do
  describe ".search" do
    context "with Interview" do
      let!(:acme)  { create(:interview, company: "Acme Corp", job_title: "Backend Engineer") }
      let!(:beta)  { create(:interview, company: "Beta Ltd",  job_title: "Frontend Developer") }
      let!(:gamma) { create(:interview, company: "Gamma Inc", job_title: "DevOps Engineer") }

      it "matches by company substring (case-insensitive)" do
        expect(Interview.search("acme")).to contain_exactly(acme)
      end

      it "matches by job_title substring" do
        expect(Interview.search("engineer")).to contain_exactly(acme, gamma)
      end

      it "returns all records when query is blank" do
        expect(Interview.search("")).to contain_exactly(acme, beta, gamma)
      end

      it "returns empty when nothing matches" do
        expect(Interview.search("zzznomatch")).to be_empty
      end

      it "sanitizes LIKE wildcards in query" do
        expect(Interview.search("%")).to be_empty
      end
    end

    context "with ApplicationMail" do
      let!(:acme_mail)  { create(:application_mail, company: "Acme Corp",  job_title: "SRE") }
      let!(:other_mail) { create(:application_mail, company: "Other Corp", job_title: "SRE Manager") }

      it "matches by company" do
        expect(ApplicationMail.search("acme")).to contain_exactly(acme_mail)
      end

      it "matches by job_title" do
        expect(ApplicationMail.search("SRE")).to contain_exactly(acme_mail, other_mail)
      end
    end
  end
end
