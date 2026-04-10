# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::SearchFormComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:url)       { "/items" }
  let(:clear_url) { "/items" }

  context "without a query" do
    let(:component) { described_class.new(url: url, query: nil, clear_url: clear_url) }

    it "renders a GET form" do
      expect(rendered.css("form[method='get']")).to be_present
    end

    it "renders the text input for :q" do
      expect(rendered.css("input[name='q']")).to be_present
    end

    it "renders the submit button" do
      expect(rendered.css("input[type='submit'][value='Search']")).to be_present
    end

    it "does not render the Clear link" do
      expect(rendered.css("a").map(&:text)).not_to include("Clear")
    end

    it "uses the default placeholder" do
      expect(rendered.css("input[name='q']").first["placeholder"]).to eq("Search…")
    end
  end

  context "with a query" do
    let(:component) { described_class.new(url: url, query: "foo", clear_url: clear_url) }

    it "pre-fills the input with the query value" do
      expect(rendered.css("input[name='q'][value='foo']")).to be_present
    end

    it "renders the Clear link pointing to clear_url" do
      clear_link = rendered.css("a").find { |a| a.text.strip == "Clear" }
      expect(clear_link).to be_present
      expect(clear_link["href"]).to eq(clear_url)
    end
  end

  context "with a custom placeholder" do
    let(:component) { described_class.new(url: url, query: nil, clear_url: clear_url, placeholder: "Find something…") }

    it "renders the custom placeholder" do
      expect(rendered.css("input[name='q']").first["placeholder"]).to eq("Find something…")
    end
  end
end
