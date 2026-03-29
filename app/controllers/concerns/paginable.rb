# frozen_string_literal: true

module Paginable
  extend ActiveSupport::Concern

  included do
    class_attribute :paginable_sortable,           default: []
    class_attribute :paginable_per_page,           default: [ 20, 50, 100 ]
    class_attribute :paginable_default_sort,       default: nil
    class_attribute :paginable_default_direction,  default: :desc
  end

  class_methods do
    def paginable(sortable: [], per_page: [ 20, 50, 100 ], default_sort: nil, default_direction: :desc)
      self.paginable_sortable          = sortable
      self.paginable_per_page          = per_page
      self.paginable_default_sort      = default_sort
      self.paginable_default_direction = default_direction
      before_action :set_pagination_params
    end
  end

  private

  def set_pagination_params
    @sort             = resolve_sort(paginable_sortable, default: paginable_default_sort)
    @direction        = resolve_direction(default: paginable_default_direction)
    @per_page         = resolve_per_page(paginable_per_page)
    @per_page_options = paginable_per_page
  end

  def paginate(collection)
    scope = @sort.present? ? collection.order(@sort => @direction) : collection
    pagy(scope, limit: @per_page)
  end

  def resolve_per_page(options)
    options.map(&:to_s).include?(params[:per_page]) ? params[:per_page].to_i : options.first
  end

  def resolve_sort(columns, default:)
    columns.include?(params[:sort]) ? params[:sort] : default.to_s
  end

  def resolve_direction(default: :desc)
    params[:direction] == "asc" ? :asc : default
  end
end
