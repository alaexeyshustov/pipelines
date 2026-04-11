# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::FlashComponent, type: :component do
  let(:flash_hash) { ActionDispatch::Flash::FlashHash.new }

  it "renders nothing when flash is empty" do
    render_inline(described_class.new(flash: flash_hash))
    expect(page.text).to be_blank
  end

  it "renders notice message with green styles" do
    flash_hash[:notice] = "Success message"
    render_inline(described_class.new(flash: flash_hash))

    expect(page).to have_text("Success message")
    expect(page).to have_css(".bg-green-50.text-green-800")
  end

  it "renders alert message with red styles" do
    flash_hash[:alert] = "Alert message"
    render_inline(described_class.new(flash: flash_hash))

    expect(page).to have_text("Alert message")
    expect(page).to have_css(".bg-red-50.text-red-800")
  end

  it "renders other message types with blue styles" do
    flash_hash[:info] = "Info message"
    render_inline(described_class.new(flash: flash_hash))

    expect(page).to have_text("Info message")
    expect(page).to have_css(".bg-blue-50.text-blue-800")
  end
end
