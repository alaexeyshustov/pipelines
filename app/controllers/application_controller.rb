class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :filters
  include Pagy::Method

  Filters = Data.define(:path, :q, :per_page, :page, :sort, :direction, :per_page_options)
  class Filters
    def initialize(per_page_options: nil, **kwargs)
      super(per_page_options:, **kwargs)
    end

    def to_full_path(params: {})
      query_params = {
        q: q,
        per_page: per_page,
        page: page,
        sort: sort,
        direction: direction
      }.merge(params).compact

      "#{path}?#{query_params.to_query}"
    end
  end

  private

  def filters
    @filters ||= Filters.new(
      path: request.path,
      q: params[:q],
      per_page: params[:per_page],
      page: params[:page],
      sort: params[:sort],
      direction: params[:direction]
    )
  end

  def flash_for(result)
    result.ok? ? { notice: result.message } : { alert: result.message }
  end
end
