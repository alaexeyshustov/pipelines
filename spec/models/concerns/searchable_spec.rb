
require "rails_helper"

RSpec.describe Searchable do
  describe ".search" do
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

    context "with ApplicationMail" do
      it "is searchable by company" do
        mail = create(:application_mail, company: "SRE Corp", job_title: "Engineer")
        create(:application_mail, company: "Other Corp", job_title: "Manager")
        expect(ApplicationMail.search("SRE Corp")).to contain_exactly(mail)
      end

      it "is searchable by job_title" do
        mail = create(:application_mail, company: "Acme", job_title: "Site Reliability Engineer")
        create(:application_mail, company: "Beta", job_title: "Product Manager")
        expect(ApplicationMail.search("reliability")).to contain_exactly(mail)
      end
    end
  end
end
