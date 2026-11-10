require "rails_helper"

RSpec.describe "Tag pages (base controller)" do
  let!(:tag) { create(:tag, name: "finance") }
  let!(:bank) { create(:subtag, tag:, name: "bank") }
  let!(:salary) { create(:subtag, tag:, name: "salary") }

  def tag_email(subject:, subtag: nil, tag: self.tag, **attrs)
    create(:email, subject:, **attrs).tap { |email| create(:tagging, taggable: email, tag:, subtag:) }
  end

  def tag_document(title:, subtag: nil, tag: self.tag, **attrs)
    create(:document, title:, **attrs).tap { |doc| create(:tagging, taggable: doc, tag:, subtag:) }
  end

  it "defines one page per fixed tag" do
    expect(Tag::NAMES.map { |name| send(:"tag_pages_#{name}_path") }.uniq.size).to eq(6)
  end

  it "lists emails and documents carrying the tag, and nothing else" do
    tag_email(subject: "Bank statement")
    tag_document(title: "Tax form")
    other = create(:tag, name: "medical")
    tag_email(subject: "Dentist reminder", tag: other)
    create(:email, subject: "Untagged mail")

    get tag_pages_finance_path

    expect(response).to be_successful
    expect(response.body).to include("Bank statement", "Tax form")
    expect(response.body).not_to include("Dentist reminder", "Untagged mail")
  end

  it "renders the rows in the client-paginated data table, with the document title as a link" do
    document = tag_document(title: "Tax <b>form</b>")

    get tag_pages_finance_path

    expect(response.body).to include('data-controller="data-table"')
    expect(response.body).to include(%(href="#{document_path(document)}"))
    expect(response.body).not_to include("Tax <b>form</b>")
  end

  it "renders an empty page when the tag row does not exist" do
    Tag.where(name: "child").destroy_all
    get tag_pages_child_path
    expect(response).to be_successful
    expect(response.body).to include("Nothing tagged")
  end

  it "shows a subtag chip for each subtag of the tag" do
    get tag_pages_finance_path
    expect(response.body).to include("bank", "salary")
  end

  it "filters by subtag" do
    tag_email(subject: "Bank statement", subtag: bank)
    tag_email(subject: "Payslip", subtag: salary)

    get tag_pages_finance_path, params: { subtag: "bank" }

    expect(response.body).to include("Bank statement")
    expect(response.body).not_to include("Payslip")
  end

  describe "type filter" do
    before do
      tag_email(subject: "Bank statement")
      tag_document(title: "Tax form")
    end

    it "shows only documents" do
      get tag_pages_finance_path, params: { type: "document" }
      expect(response.body).to include("Tax form")
      expect(response.body).not_to include("Bank statement")
    end

    it "shows only emails" do
      get tag_pages_finance_path, params: { type: "email" }
      expect(response.body).to include("Bank statement")
      expect(response.body).not_to include("Tax form")
    end
  end

  describe "date range" do
    it "defaults to the last 90 days" do
      tag_email(subject: "Recent mail", date: 10.days.ago)
      tag_email(subject: "Ancient mail", date: 120.days.ago)
      tag_document(title: "Old scan", created_at: 120.days.ago)

      get tag_pages_finance_path

      expect(response.body).to include("Recent mail")
      expect(response.body).not_to include("Ancient mail", "Old scan")
    end

    it "honours explicit from and to dates" do
      tag_email(subject: "Ancient mail", date: 120.days.ago)
      tag_email(subject: "Recent mail", date: 10.days.ago)

      get tag_pages_finance_path, params: { from: 130.days.ago.to_date.to_s, to: 100.days.ago.to_date.to_s }

      expect(response.body).to include("Ancient mail")
      expect(response.body).not_to include("Recent mail")
    end

    it "falls back to the default for an unparseable date" do
      tag_email(subject: "Recent mail", date: 10.days.ago)
      get tag_pages_finance_path, params: { from: "garbage" }
      expect(response).to be_successful
      expect(response.body).to include("Recent mail")
    end
  end

  describe "full-text search" do
    it "searches within the tag only, with highlighted snippets" do
      tag_email(subject: "Invoice", body: "salary attached")
      create(:email, subject: "Other", body: "salary elsewhere")
      other = create(:tag, name: "medical")
      tag_document(title: "Pay doc", text: "salary for medical", tag: other)

      get tag_pages_finance_path, params: { q: "salary" }

      expect(response.body).to include("Invoice", "<mark>salary</mark>")
      expect(response.body).not_to include("Other", "Pay doc")
    end

    it "escapes raw content in snippets" do
      tag_email(subject: "Invoice", body: "salary <script>alert(1)</script>")
      get tag_pages_finance_path, params: { q: "salary" }
      expect(response.body).not_to include("<script>alert(1)")
    end

    it "does not raise on hostile input" do
      get tag_pages_finance_path, params: { q: %q(" OR * NEAR( ) -- ' AND) }
      expect(response).to be_successful
    end
  end

  it "combines subtag, type, date range and search" do
    tag_email(subject: "Match", body: "salary", subtag: bank, date: 5.days.ago)
    tag_email(subject: "Wrong subtag", body: "salary", subtag: salary, date: 5.days.ago)
    tag_email(subject: "Too old", body: "salary", subtag: bank, date: 200.days.ago)
    tag_email(subject: "No term", body: "nothing", subtag: bank, date: 5.days.ago)
    tag_document(title: "Wrong type", text: "salary", subtag: bank)

    get tag_pages_finance_path, params: { subtag: "bank", type: "email", q: "salary" }

    expect(response.body).to include("Match")
    expect(response.body).not_to include("Wrong subtag", "Too old", "No term", "Wrong type")
  end

  it "avoids N+1 queries across many rows" do
    count_queries = lambda do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get tag_pages_finance_path }
      queries
    end
    2.times { |i| tag_email(subject: "Mail #{i}", subtag: bank, interview: create(:interview)) }
    baseline = count_queries.call
    5.times { |i| tag_email(subject: "More #{i}", subtag: bank, interview: create(:interview)) }
    expect(count_queries.call).to eq(baseline)
  end
end
