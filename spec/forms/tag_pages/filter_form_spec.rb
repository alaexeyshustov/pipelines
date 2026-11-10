require "rails_helper"

RSpec.describe TagPages::FilterForm do
  include ActiveSupport::Testing::TimeHelpers

  before { travel_to(Time.zone.local(2026, 11, 3, 12)) }

  it "defaults the date range to the last 90 days" do
    form = described_class.new
    expect(form.from_date).to eq(Date.new(2026, 8, 5))
    expect(form.to_date).to be_nil
  end

  it "parses explicit dates and ignores unparseable ones" do
    form = described_class.new(from: "2026-01-02", to: "2026-02-03")
    expect([ form.from_date, form.to_date ]).to eq([ Date.new(2026, 1, 2), Date.new(2026, 2, 3) ])
    expect(described_class.new(from: "garbage", to: "nope").from_date).to eq(Date.new(2026, 8, 5))
    expect(described_class.new(to: "nope").to_date).to be_nil
  end

  it "defaults from relative to an old to date, so the range is never inverted" do
    form = described_class.new(to: "2026-01-31")
    expect([ form.from_date, form.to_date ]).to eq([ Date.new(2025, 11, 2), Date.new(2026, 1, 31) ])
  end

  it "defaults from to 90 days before any to date" do
    expect(described_class.new(to: "2026-10-01").from_date).to eq(Date.new(2026, 7, 3))
  end

  it "reads the type filter, treating anything unknown as both" do
    expect(described_class.new(type: "email")).to have_attributes(include_emails?: true, include_documents?: false)
    expect(described_class.new(type: "document")).to have_attributes(include_emails?: false, include_documents?: true)
    expect(described_class.new(type: "bogus")).to have_attributes(include_emails?: true, include_documents?: true)
  end

  it "strips the query" do
    expect(described_class.new(q: "  salary ").query).to eq("salary")
    expect(described_class.new(q: "  ").query).to be_nil
  end

  it "builds chip and form params without default noise" do
    expect(described_class.new(q: "x", subtag: "bank").to_params).to eq({ q: "x", subtag: "bank" })
  end
end
