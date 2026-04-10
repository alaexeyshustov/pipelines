# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chats::DetailCardComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:ai_model) { build_stubbed(:model, name: "mistral-large") }
  let(:chat) do
    build_stubbed(:chat,
                  model: ai_model,
                  created_at: Time.zone.parse("2026-04-08 10:00:00"),
                  updated_at: Time.zone.parse("2026-04-08 11:30:00"))
  end
  let(:component) { described_class.new(chat: chat) }

  before { allow(chat).to receive(:messages).and_return([ 1, 2, 3 ]) }

  it "renders the detail card wrapper" do
    expect(rendered.css("[data-testid='chat-detail-card']")).to be_present
  end

  it "renders the model name" do
    expect(rendered.text).to include("mistral-large")
  end

  it "renders the message count" do
    expect(rendered.text).to include("3")
  end

  it "renders formatted created_at" do
    expect(rendered.text).to include("Apr 8, 2026 10:00:00")
  end

  it "renders formatted updated_at" do
    expect(rendered.text).to include("Apr 8, 2026 11:30:00")
  end

  context "when model is nil" do
    let(:chat) do
      build_stubbed(:chat,
                    model: nil,
                    created_at: Time.zone.parse("2026-04-08 10:00:00"),
                    updated_at: Time.zone.parse("2026-04-08 10:00:00"))
    end

    it "renders an em-dash for model" do
      expect(component.model_name_value).to eq("—")
    end
  end

  describe "#formatted_created_at" do
    it "returns formatted timestamp" do
      expect(component.formatted_created_at).to eq("Apr 8, 2026 10:00:00")
    end
  end

  describe "#formatted_updated_at" do
    it "returns formatted timestamp" do
      expect(component.formatted_updated_at).to eq("Apr 8, 2026 11:30:00")
    end
  end
end
