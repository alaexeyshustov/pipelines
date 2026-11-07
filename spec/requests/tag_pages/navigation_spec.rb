require "rails_helper"

RSpec.describe "Tag page navigation" do
  it "links one page per tag from the sidebar" do
    get tags_path
    hrefs = Nokogiri::HTML(response.body).css("[data-testid='sidebar'] a").pluck("href")
    Tag::NAMES.each do |name|
      expect(hrefs).to include(send(:"tag_pages_#{name}_path"))
    end
  end
end
