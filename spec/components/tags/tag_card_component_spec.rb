require "rails_helper"

RSpec.describe Tags::TagCardComponent, type: :component do
  it "renders the tag, its subtags and an add form" do
    tag = build_stubbed(:tag, name: "finance")
    subtags = [ build_stubbed(:subtag, tag:, name: "bank") ]
    render_inline(described_class.new(tag:, subtags:, form_url: "/tags/#{tag.id}/subtags"))
    expect(page).to have_text("finance")
    expect(page).to have_text("bank")
    expect(page).to have_css("form[action='/tags/#{tag.id}/subtags']")
  end

  it "shows errors" do
    tag = build_stubbed(:tag)
    errors = ActiveModel::Errors.new(Subtag.new).tap { |e| e.add(:name, "can't be blank") }
    render_inline(described_class.new(tag:, subtags: [], form_url: "/x", errors:))
    expect(page).to have_text("can't be blank")
  end
end
