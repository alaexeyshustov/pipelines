# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TableComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:record_class) { Data.define(:id, :name, :status) }
  let(:records) do
    [
      record_class.new(id: 1, name: "Acme Corp", status: "Active"),
      record_class.new(id: 2, name: "Globex", status: "Pending")
    ]
  end




  context "with collection and columns" do
    let(:component) do
      described_class.new(collection: records).tap do |c|
        c.with_columns([
          { key: :name, label: "Name" },
          { key: :status, label: "Status" },
          {}
        ])
      end
    end

    before { render_inline(component) }

    it "renders the table wrapper" do
      expect(rendered.css("div.bg-white.rounded-xl")).to be_present
    end

    it "renders a table element" do
      expect(rendered.css("table.w-full")).to be_present
    end

    it "renders thead with 3 column headers" do
      expect(rendered.css("thead th").size).to eq(3)
    end

    it "renders column headers with correct labels" do
      headers = rendered.css("thead th").map { |h| h.text.strip }
      expect(headers).to eq([ "Name", "Status", "" ])
    end

    it "renders labeled columns with default classes" do
      expect(rendered.css("th.px-4.py-3").first["class"]).to include("font-medium", "text-gray-600")
    end

    it "renders empty action column with minimal classes" do
      last_th = rendered.css("thead th").last
      expect(last_th["class"]).to eq("px-4 py-3")
    end

    it "renders a row per record" do
      expect(rendered.css("tbody tr.hover\\:bg-gray-50").size).to eq(2)
    end

    it "renders cell values for each record" do
      first_row_cells = rendered.css("tbody tr:first-child td")
      expect(first_row_cells[0].text.strip).to eq("Acme Corp")
      expect(first_row_cells[1].text.strip).to eq("Active")
    end

    it "renders all records" do
      second_row_cells = rendered.css("tbody tr:last-child td")
      expect(second_row_cells[0].text.strip).to eq("Globex")
      expect(second_row_cells[1].text.strip).to eq("Pending")
    end
  end

  context "when collection is empty" do
    let(:component) { described_class.new(collection: [], empty_message: "No records found.") }

    before do
      component.with_columns([ { label: "Name" }, { label: "Value" } ])
      render_inline(component)
    end

    it "renders the empty message" do
      expect(rendered.css("td").first.text.strip).to eq("No records found.")
    end

    it "sets colspan to column count" do
      expect(rendered.css("td").first["colspan"]).to eq("2")
    end

    it "does not render row content" do
      expect(rendered.css("tr.hover\\:bg-gray-50")).to be_empty
    end
  end

  context "with compact style columns" do
    let(:component) { described_class.new(collection: []) }

    before do
      component.with_columns([ { label: "Status", style: :compact } ])
      render_inline(component)
    end

    it "renders compact header classes" do
      th = rendered.css("thead th").first
      expect(th["class"]).to include("text-xs", "font-semibold", "uppercase")
    end
  end

  context "with block content in column" do
    let(:component) { described_class.new(collection: []) }

    before do
      component.with_column { "<a href='/'>Link</a>".html_safe }
      render_inline(component)
    end

    it "renders block content in the header cell" do
      expect(rendered.css("thead th a")).to be_present
    end
  end

  context "with key-derived label" do
    let(:component) { described_class.new(collection: []) }

    before { render_inline(component) }

    it "derives label from a simple key" do
      component.with_columns([ { key: "company" } ])
      render_inline(component)
      expect(rendered.css("thead th").first.text.strip).to eq("Company")
    end

    it "derives label from an underscored key" do
      component.with_columns([ { key: "agent_class" } ])
      render_inline(component)
      expect(rendered.css("thead th").first.text.strip).to eq("Agent Class")
    end

    it "allows explicit label to override key" do
      component.with_columns([ { key: "status", label: "Current Status" } ])
      render_inline(component)
      expect(rendered.css("thead th").first.text.strip).to eq("Current Status")
    end
  end

  context "with a custom cell proc" do
    let(:component) { described_class.new(collection: records) }

    before do
      component.with_columns([ { key: :name, label: "Name", cell: ->(r) { r.name.upcase } } ])
      render_inline(component)
    end

    it "renders cell content via the proc" do
      expect(rendered.css("tbody td").first.text.strip).to eq("ACME CORP")
    end
  end

  context "with a component and props" do
    let(:component) { described_class.new(collection: records) }

    before do
      component.with_columns([
        {
          key: :status,
          label: "Status",
          component: UI::StatusBadgeComponent,
          props: ->(r) { { label: r.status, variant: :success } }
        }
      ])
      render_inline(component)
    end

    it "renders the ViewComponent in the cell" do
      expect(rendered.css("tbody td span").first.text.strip).to eq("Active")
    end

    it "applies the component variant classes" do
      expect(rendered.css("tbody td span").first["class"]).to include("bg-green-50")
    end
  end

  context "with an action column" do
    let(:component) do
      described_class.new(collection: records).tap do |c|
        c.with_columns([ { key: :name, label: "Name" } ])
        c.with_action_column(
          actions: ->(_record) {
            [
              { label: "Edit", url: "/edit", variant: :primary },
              { label: "Delete", url: "/delete", method: :delete, variant: :danger, confirm: "Sure?" }
            ]
          }
        )
      end
    end

    before { render_inline(component) }

    it "renders an empty action column header" do
      last_th = rendered.css("thead th").last
      expect(last_th.text.strip).to eq("")
    end

    it "renders action links in each row" do
      first_row = rendered.css("tbody tr").first
      expect(first_row.css("a").map { |a| a.text.strip }).to include("Edit")
    end

    it "renders action cells for all records" do
      expect(rendered.css("tbody tr").size).to eq(records.size)
    end

    it "sets total_columns including action column" do
      expect(rendered.css("thead th").size).to eq(2)
    end
  end

  context "with batch actions" do
    let(:pagy) { instance_double(Pagy::Offset, limit: 25, last: 3, series_nav: "") }
    let(:filters) do
      ApplicationController::Filters.new(
        path: "/items", q: nil, per_page: "25", page: nil, sort: "", direction: "desc",
        per_page_options: [ 10, 25, 50 ]
      )
    end
    let(:component) do
      described_class.new(
        collection: records,
        selectable: true,
        pagy: pagy,
        filters: filters
      ).tap do |c|
        c.with_columns([ { key: :name, label: "Name" } ])
        c.with_batch_action(type: :raw) { '<button id="del">Delete</button>'.html_safe }
        c.with_batch_action(type: :raw) { '<button id="exp">Export</button>'.html_safe }
      end
    end

    before { render_inline(component) }

    it "renders the select all button" do
      expect(rendered.css("button[data-batch-target='selectAllBtn']")).to be_present
    end

    it "renders each batch action slot" do
      expect(rendered.css("button#del")).to be_present
      expect(rendered.css("button#exp")).to be_present
    end

    it "renders per-page links for each option" do
      links = rendered.css("div.ml-auto a")
      expect(links.map(&:text).map(&:strip)).to eq(%w[10 25 50])
    end

    it "highlights the active per-page link" do
      active = rendered.css("div.ml-auto a").find { |a| a["class"].include?("bg-gray-200") }
      expect(active.text.strip).to eq("25")
    end

    it "does not render the toolbar when not selectable" do
      plain = described_class.new(collection: records)
      plain.with_columns([ { key: :name, label: "Name" } ])
      result = render_inline(plain)
      expect(result.css("button[data-batch-target='selectAllBtn']")).to be_empty
    end
  end

  context "with sortable columns" do
    let(:filters) do
      ApplicationController::Filters.new(
        path: "/records", q: nil, per_page: nil, page: nil, sort: "name", direction: "asc"
      )
    end
    let(:component) do
      described_class.new(collection: records, filters: filters).tap do |c|
        c.with_columns([
          { key: "name",   label: "Name" },
          { key: "status", label: "Status" }
        ])
      end
    end

    before { render_inline(component) }

    it "renders sort links in column headers" do
      expect(rendered.css("thead th a").size).to eq(2)
    end

    it "links to the correct sort URL" do
      name_link = rendered.css("thead th a").first
      expect(name_link["href"]).to include("sort=name")
    end

    it "toggles direction for the active sort column" do
      name_link = rendered.css("thead th a").first
      expect(name_link["href"]).to include("direction=desc")
    end

    it "uses desc for inactive columns (first click)" do
      status_link = rendered.css("thead th a").last
      expect(status_link["href"]).to include("direction=desc")
    end

    it "renders a direction indicator on the active column" do
      active_th = rendered.css("thead th").first
      expect(active_th.css("span.text-gray-400").text).to eq("↑")
    end

    it "does not render a direction indicator on inactive columns" do
      inactive_th = rendered.css("thead th").last
      expect(inactive_th.css("span.text-gray-400")).to be_empty
    end
  end
end
