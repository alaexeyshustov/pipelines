# frozen_string_literal: true

module UI
  class TableComponentPreview < ViewComponent::Preview
    Person = Data.define(:name, :status, :id)

    SAMPLE_RECORDS = [
      Person.new(name: "Acme Corp", status: "Active", id: 1),
      Person.new(name: "Globex Industries", status: "Pending", id: 2),
      Person.new(name: "Initech", status: "Rejected", id: 3)
    ].freeze

    def default
      render(UI::TableComponent.new(collection: SAMPLE_RECORDS)) do |t|
        t.with_columns([
          { key: :name,   label: "Name",   variant: :strong },
          { key: :status, label: "Status", variant: :subtle }
        ])
        t.with_action_column(
          actions: ->(_record) {
            [
              { label: "Edit", url: "#", variant: :primary },
              { label: "Delete", url: "#", method: :delete, variant: :danger, confirm: "Delete?" }
            ]
          }
        )
      end
    end

    def empty_state
      render(UI::TableComponent.new(collection: [], empty_message: "No records found.")) do |t|
        t.with_columns([
          { key: :name,   label: "Name" },
          { key: :status, label: "Status" }
        ])
        t.with_action_column
      end
    end

    def compact_headers
      render(UI::TableComponent.new(collection: SAMPLE_RECORDS)) do |t|
        t.with_columns([
          { key: :name,   label: "Name",   style: :compact, variant: :strong },
          { key: :status, label: "Status", style: :compact, variant: :subtle }
        ])
        t.with_action_column(
          style: :compact,
          actions: ->(_record) {
            [ { label: "Details", url: "#", variant: :primary } ]
          }
        )
      end
    end

    def with_custom_cell
      render(UI::TableComponent.new(collection: SAMPLE_RECORDS)) do |t|
        t.with_columns([
          { key: :name,   label: "Name",   variant: :strong },
          { key: :status, label: "Status", cell: ->(record) { record.status.upcase } }
        ])
      end
    end

    def with_component_cell
      render(UI::TableComponent.new(collection: SAMPLE_RECORDS)) do |t|
        t.with_columns([
          { key: :name, label: "Name", variant: :strong },
          {
            key: :status, label: "Status",
            component: UI::StatusBadgeComponent,
            props: ->(record) {
              variant = record.status == "Active" ? :success : :neutral
              { label: record.status, variant: variant }
            }
          }
        ])
      end
    end

    def with_batch_actions
      pagy = Struct.new(:limit).new(25)
      filters = ApplicationController::Filters.new(
        path: "/preview", q: nil, per_page: "25", page: nil, sort: "", direction: "desc",
        per_page_options: [ 10, 25, 50 ]
      )
      render(UI::TableComponent.new(
        collection: SAMPLE_RECORDS,
        selectable: true,
        pagy: pagy,
        filters: filters
      )) do |t|
        t.with_batch_action(
          type: :button, label: "Delete", url: "#", action: "delete",
          variant: :danger, confirm: "Delete selected records?"
        )
        t.with_batch_action(
          type: :dialog, label: "Merge", dialog_title: "Merge selected?",
          url: "#", action: "merge", confirm: "Merge", variant: :primary
        )
        t.with_columns([
          { key: :name,   label: "Name",   variant: :strong },
          { key: :status, label: "Status", variant: :subtle }
        ])
      end
    end

    def with_sorting
      filters = ApplicationController::Filters.new(
        path: "/preview", q: nil, per_page: nil, page: nil, sort: "name", direction: "asc"
      )
      render(UI::TableComponent.new(collection: SAMPLE_RECORDS, filters: filters)) do |t|
        t.with_columns([
          { key: :name,   label: "Name" },
          { key: :status, label: "Status" }
        ])
      end
    end
  end
end
