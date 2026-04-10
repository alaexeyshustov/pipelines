# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::PaginationComponent, type: :component do
  let(:nav_html) { '<nav class="flex items-center gap-1 mt-6 justify-center" aria-label="Pages"><a href="/items?page=2">Next</a></nav>' }
  let(:multi_page_pagy) { instance_double(Pagy::Offset, last: 3, series_nav: nav_html) }
  let(:single_page_pagy) { instance_double(Pagy::Offset, last: 1) }

  describe "#render?" do
    it "renders when there are multiple pages" do
      component = described_class.new(pagy: multi_page_pagy)
      expect(component.render?).to be true
    end

    it "does not render when there is only one page" do
      component = described_class.new(pagy: single_page_pagy)
      expect(component.render?).to be false
    end
  end

  describe "output" do
    subject(:rendered) { render_inline(described_class.new(pagy: multi_page_pagy)) }

    it "renders a nav element" do
      expect(rendered.css("nav[aria-label='Pages']")).to be_present
    end

    it "delegates html to pagy#series_nav" do
      expect(rendered.to_html).to include("Next")
    end
  end
end
