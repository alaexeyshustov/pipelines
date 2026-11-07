require "rails_helper"

RSpec.describe TagPages::Search do
  let(:tag) { create(:tag, name: "finance") }
  let(:old_email) { create(:email, subject: "Salary salary", body: "salary salary salary", date: 10.days.ago) }
  let(:new_email) { create(:email, subject: "Other", body: "mentions salary once among many other words", date: 2.days.ago) }
  let(:document) do
    create(:document, title: "Payslip", text: "salary among many other words in a long text", created_at: 1.day.ago)
  end

  def search(**params)
    described_class.call(tag:, filter: TagPages::FilterForm.new(params))
  end

  before do
    [ old_email, new_email, document ].each { |record| create(:tagging, taggable: record, tag:) }
  end

  it "orders emails and documents together by date, newest first, even with a query" do
    expect(search(q: "salary").map(&:record)).to eq([ document, new_email, old_email ])
  end

  it "orders a single type by match rank when there is a query" do
    expect(search(q: "salary", type: "email").map(&:record)).to eq([ old_email, new_email ])
  end
end
