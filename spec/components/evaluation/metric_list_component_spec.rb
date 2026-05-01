# frozen_string_literal: true

require "rails_helper"

RSpec.describe Evaluation::MetricListComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:metric_class) do
    Data.define(:id, :name, :description, :weight, :active) do
      def active? = active
    end
  end

  let(:metrics) do
    [
      metric_class.new(id: 1, name: "clarity", description: "Response is clear", weight: 1.5, active: true),
      metric_class.new(id: 2, name: "accuracy", description: "Answer is correct", weight: 2.0, active: false)
    ]
  end

  context "with metrics" do
    let(:component) { described_class.new(metrics: metrics) }

    it "renders a table" do
      expect(rendered.css("table")).to be_present
    end

    it "renders metric names" do
      expect(rendered.text).to include("clarity")
      expect(rendered.text).to include("accuracy")
    end

    it "renders metric descriptions" do
      expect(rendered.text).to include("Response is clear")
    end

    it "renders weights" do
      expect(rendered.text).to include("1.5")
      expect(rendered.text).to include("2.0")
    end

    it "renders active status" do
      expect(rendered.text).to include("Yes")
      expect(rendered.text).to include("No")
    end

    it "renders edit links" do
      expect(rendered.css("a[href*='edit']").size).to eq(2)
    end
  end

  context "with empty collection" do
    let(:component) { described_class.new(metrics: []) }

    it "renders empty message" do
      expect(rendered.text).to include("No metrics found.")
    end
  end
end
