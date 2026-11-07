require "rails_helper"

RSpec.describe Documents::DuplicatesComponent, type: :component do
  let(:document) { create(:document, title: "Lease.pdf") }
  let(:other) { create(:document, title: "Lease scan.pdf") }

  def render_for(*duplicates) = render_inline(described_class.new(document:, duplicates:))

  it "renders nothing without candidates" do
    render_for

    expect(page).to have_no_text("Possible duplicates")
  end

  it "links the other document with its similarity" do
    duplicate = DocumentDuplicate.flag!(document, other, similarity: 0.973)
    render_for(duplicate)

    expect(page).to have_link("Lease scan.pdf", href: "/documents/#{other.id}")
    expect(page).to have_text("97.3%")
  end

  it "offers confirm and dismiss for a pending pair" do
    duplicate = DocumentDuplicate.flag!(document, other, similarity: 0.973)
    render_for(duplicate)

    expect(page).to have_css("form[action='/documents/#{document.id}/duplicates/#{duplicate.id}/confirm'] button", text: "Confirm")
    expect(page).to have_css("form[action='/documents/#{document.id}/duplicates/#{duplicate.id}/dismiss'] button", text: "Dismiss")
  end

  it "marks a confirmed pair without offering confirm again" do
    render_for(DocumentDuplicate.flag!(other, document, similarity: 0.96).tap(&:confirmed!))

    expect(page).to have_text("Confirmed duplicate")
    expect(page).to have_no_button("Confirm")
    expect(page).to have_button("Dismiss")
  end
end
