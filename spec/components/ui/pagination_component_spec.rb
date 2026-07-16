
require "rails_helper"

RSpec.describe UI::PaginationComponent, type: :component do
  let(:request) do
    ActionDispatch::Request.new(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO"      => "/items",
      "QUERY_STRING"   => "",
      "rack.input"     => StringIO.new,
      "SERVER_NAME"    => "www.example.com",
      "SERVER_PORT"    => "80"
    )
  end
  let(:multi_page_pagy)  { Pagy::Offset.new(count: 75, limit: 25, page: 1, request: request) }
  let(:single_page_pagy) { Pagy::Offset.new(count: 25, limit: 25, page: 1, request: request) }

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
