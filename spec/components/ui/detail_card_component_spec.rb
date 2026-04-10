# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::DetailCardComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:entity_class) { Data.define(:company, :status, :applied_at, :email_id) }
  let(:entity) { entity_class.new(company: "Acme Corp", status: "having_interviews", applied_at: Date.new(2026, 1, 15), email_id: "abc123") }
  let(:attributes) do
    [
      { label: "Company",    attribute: :company },
      { label: "Status",     attribute: :status,     type: :badge,
        variant_map: { "having_interviews" => :info, "rejected" => :danger } },
      { label: "Applied At", attribute: :applied_at, type: :date },
      { label: "Email ID",   attribute: :email_id,   type: :mono }
    ]
  end
  let(:component) { described_class.new(entity: entity, attributes: attributes) }





  # Tracer bullet: renders the card wrapper
  it "renders the detail-card wrapper" do
    expect(rendered.css("[data-testid='detail-card']")).to be_present
  end

  it "renders a dt for each attribute label" do
    labels = rendered.css("dt").map(&:text).map(&:strip)
    expect(labels).to eq([ "Company", "Status", "Applied At", "Email ID" ])
  end

  context "with a plain text attribute" do
    it "renders the entity value" do
      expect(rendered.css("dd").first.text.strip).to eq("Acme Corp")
    end
  end

  context "with a nil plain text attribute" do
    let(:entity) { entity_class.new(company: nil, status: "rejected", applied_at: nil, email_id: nil) }

    it "renders an em-dash placeholder" do
      expect(rendered.css("dd").first.text.strip).to eq("—")
    end
  end

  context "with a :badge type attribute" do
    it "renders a status badge span" do
      badge_dd = rendered.css("dd")[1]
      expect(badge_dd.css("span").text.strip).to eq("Having interviews")
    end

    it "applies the mapped variant classes" do
      badge_span = rendered.css("dd")[1].css("span").first
      expect(badge_span["class"]).to include("text-blue-700")
    end

    it "falls back to neutral variant when value is unmapped" do
      entity_unknown = entity_class.new(company: "X", status: "offer_received", applied_at: nil, email_id: nil)
      component_unknown = described_class.new(entity: entity_unknown, attributes: attributes)
      doc = render_inline(component_unknown)
      badge_span = doc.css("dd")[1].css("span").first
      expect(badge_span["class"]).to include("text-gray-700")
    end
  end

  context "with a nil :badge attribute" do
    let(:entity) { entity_class.new(company: "X", status: nil, applied_at: nil, email_id: nil) }

    it "renders em-dash as the badge label" do
      badge_dd = rendered.css("dd")[1]
      expect(badge_dd.css("span").text.strip).to eq("—")
    end
  end

  context "with a :date type attribute" do
    it "applies the tabular-nums class" do
      date_dd = rendered.css("dd")[2]
      expect(date_dd.css("span").first["class"]).to include("tabular-nums")
    end

    it "renders the date value" do
      date_dd = rendered.css("dd")[2]
      expect(date_dd.text.strip).to eq("2026-01-15")
    end
  end

  context "with a nil :date attribute" do
    let(:entity) { entity_class.new(company: "X", status: "rejected", applied_at: nil, email_id: nil) }

    it "renders em-dash for the date" do
      date_dd = rendered.css("dd")[2]
      expect(date_dd.text.strip).to eq("—")
    end
  end

  context "with a :mono type attribute" do
    it "applies the font-mono class" do
      mono_dd = rendered.css("dd")[3]
      expect(mono_dd.css("span").first["class"]).to include("font-mono")
    end

    it "renders the value" do
      mono_dd = rendered.css("dd")[3]
      expect(mono_dd.text.strip).to eq("abc123")
    end

    context "when nil" do
      let(:entity) { entity_class.new(company: "X", status: "rejected", applied_at: nil, email_id: nil) }

      it "renders em-dash" do
        mono_dd = rendered.css("dd")[3]
        expect(mono_dd.text.strip).to eq("—")
      end
    end
  end
end
