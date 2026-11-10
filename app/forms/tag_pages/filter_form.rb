module TagPages
  # The preset filters of a tag page (query string params): subtag chip, type, date range, FTS query.
  # Unparseable dates fall back to the defaults instead of failing the page. A missing from is DEFAULT_DAYS before
  # to (or before today without a to), so an old to date never gives an inverted range.
  class FilterForm < ::BaseForm
    DEFAULT_DAYS = 90
    TYPES = %w[email document].freeze

    attribute :q, :string
    attribute :subtag, :string
    attribute :type, :string
    attribute :from, :date
    attribute :to, :date

    def query
      q.to_s.strip.presence
    end

    def subtag_name
      subtag.presence
    end

    def from_date
      from || ((to || Time.zone.today) - DEFAULT_DAYS)
    end

    def to_date
      to
    end

    def include_emails?
      type != "document"
    end

    def include_documents?
      type != "email"
    end

    # The explicitly chosen filters, for building chip links.
    def to_params
      { q: query, subtag: subtag_name, type: TYPES.include?(type) ? type : nil, from: from, to: to }.compact_blank
    end
  end
end
