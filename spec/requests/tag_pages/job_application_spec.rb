require "rails_helper"

RSpec.describe "Job application tag page" do
  let!(:tag) { create(:tag, name: "job_application") }

  def tag_item(item)
    create(:tagging, taggable: item, tag:)
    item
  end

  it "shows Company and Status columns" do
    get tag_pages_job_application_path
    expect(response.body).to include("Company", "Status")
  end

  it "shows the interview of an email" do
    interview = create(:interview, company: "Initech", status: "having_interviews")
    tag_item(create(:email, subject: "Next steps", interview:))

    get tag_pages_job_application_path

    expect(response.body).to include("Next steps", "Initech", "Having interviews")
  end

  it "uses the source email's interview for a document" do
    interview = create(:interview, company: "Globex", status: "offer_received")
    source = create(:email, interview:, subject: "Source mail")
    tag_item(create(:document, title: "Offer.pdf", email: source))

    get tag_pages_job_application_path, params: { type: "document" }

    expect(response.body).to include("Offer.pdf", "Globex", "Offer received")
  end

  it "leaves interview cells blank when there is no interview" do
    tag_item(create(:email, subject: "Plain mail"))
    tag_item(create(:document, title: "Loose.pdf", email: create(:email)))
    tag_item(create(:document, title: "Orphan.pdf", email: nil))

    get tag_pages_job_application_path

    expect(response).to be_successful
    expect(response.body).to include("Plain mail", "Loose.pdf", "Orphan.pdf")
  end

  it "is not shown on other tag pages" do
    create(:tag, name: "finance")
    get tag_pages_finance_path
    expect(response.body).not_to include("Company")
  end
end
