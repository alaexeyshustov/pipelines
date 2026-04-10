# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::ErrorMessagesComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new(errors: errors)) }

  context "when there are no errors" do
    let(:errors) { Interview.new.errors }

    it "renders nothing" do
      expect(rendered.to_html.strip).to be_empty
    end
  end

  context "when there are errors" do
    let(:errors) do
      interview = Interview.new
      interview.validate
      interview.errors
    end

    it "renders the error container" do
      expect(rendered.css("div.bg-red-50")).to be_present
    end

    it "renders the heading text" do
      expect(rendered.css("p").text).to include("Please fix the following errors")
    end

    it "renders each error message as a list item" do
      errors.full_messages.each do |msg|
        expect(rendered.css("li").map(&:text)).to include(msg)
      end
    end

    it "renders a list" do
      expect(rendered.css("ul li").length).to eq(errors.full_messages.length)
    end
  end
end
