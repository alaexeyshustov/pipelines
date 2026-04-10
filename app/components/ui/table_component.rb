# frozen_string_literal: true

module UI
  class TableComponent < ViewComponent::Base
    renders_many :columns, "UI::TableComponent::ColumnComponent"
    renders_one :action_column, "UI::TableComponent::ActionColumnComponent"
    renders_one :pagination, "UI::PaginationComponent"
    renders_many :batch_actions, "UI::BatchActionComponent"

    def initialize(collection:, empty_message: "No records found.", selectable: false, pagy: nil, filters: nil)
      @collection    = collection
      @empty_message = empty_message
      @selectable    = selectable
      @pagy          = pagy
      @filters       = filters
    end

    def with_batch_actions(action_defs)
      action_defs.each { |action| with_batch_action(**action) }
    end

    def with_columns(column_defs)
      column_defs.each do |col|
        key = col[:key]&.to_s
        with_column(
          key,
          label: col[:label],
          style: col.fetch(:style, :default),
          variant: col[:variant],
          classes: col[:classes],
          cell: col[:cell],
          badge_component: col[:badge],
          component: col[:component],
          props: col[:props],
          **sort_params_for(key)
        )
      end
    end

    def before_render
      with_pagination(pagy: @pagy) if @pagy
    end

    def empty?
      @collection.empty?
    end

    def selectable?
      @selectable
    end

    def total_columns
      count = columns.size
      count += 1 if action_column?
      count += 1 if selectable?
      count
    end

    def per_page_options
      @filters&.per_page_options
    end

    def per_page_link_class(n)
      base = "px-2 py-1 rounded border"
      if @pagy.limit == n
        "#{base} bg-gray-200 border-gray-400 font-semibold text-gray-800"
      else
        "#{base} border-gray-300 hover:bg-gray-50 text-gray-600"
      end
    end

    def per_page_url_for(n)
      @filters.to_full_path(params: { per_page: n })
    end

    private

    def sort_params_for(key)
      return {} unless @filters && key

      next_dir = (@filters.sort.to_s == key && @filters.direction.to_s == "desc") ? "asc" : "desc"
      {
        sort_url: @filters.to_full_path(params: { sort: key, direction: next_dir }),
        sort_active: @filters.sort.to_s == key,
        sort_direction: @filters.direction.to_s
      }
    end
  end
end
