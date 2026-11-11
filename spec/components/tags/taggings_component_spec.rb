require "rails_helper"

RSpec.describe Tags::TaggingsComponent, type: :component do
  let(:tag) { create(:tag, name: "finance") }
  let(:subtag) { create(:subtag, tag:, name: "bank") }
  let(:email) { create(:email) }

  def render_component(taggings: email.taggings.includes(:tag, :subtag))
    render_inline(described_class.new(taggings:, tags: Tag.includes(:subtags).order(:id), base_url: "/emails/#{email.id}/taggings"))
  end

  context "with an llm tagging" do
    let!(:tagging) { create(:tagging, taggable: email, tag:, subtag:, source: "llm", confidence: 0.87) }

    it "lists the tag, subtag, source and confidence" do
      render_component
      expect(page).to have_text("finance / bank")
      expect(page).to have_text("llm 87%")
    end

    it "offers a remove button" do
      render_component
      expect(page).to have_css("form[action='/emails/#{email.id}/taggings/#{tagging.id}'] button", text: "Remove")
    end
  end

  it "renders an add form with tag and subtag selects" do
    subtag
    render_component
    expect(page).to have_css("form[action='/emails/#{email.id}/taggings'] select[name='tagging[tag_id]']")
    expect(page).to have_css("select[name='tagging[subtag_id]'] option", text: "finance / bank")
  end

  it "says when there are no tags" do
    render_component
    expect(page).to have_text("No tags yet.")
  end

  it "shows errors" do
    errors = ActiveModel::Errors.new(Tagging.new).tap { |e| e.add(:subtag, "is bad") }
    render_inline(described_class.new(taggings: [], tags: [], base_url: "/x", errors:))
    expect(page).to have_text("is bad")
  end
end
