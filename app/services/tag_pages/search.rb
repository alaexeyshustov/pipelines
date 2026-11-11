module TagPages
  # The emails and documents carrying +tag+, narrowed by a FilterForm (subtag, type, date range, FTS query).
  # With a query on a single kind, rows are ordered best match first. Otherwise (no query, or emails and documents
  # together, whose bm25 ranks come from two FTS indexes and cannot be compared) newest first. The result is capped at
  # LIMIT rows in all (each kind is fetched up to LIMIT, then the merged list is cut); the page shows them in a
  # client-paginated table, so LIMIT is generous and older rows are reached by narrowing the date range or the search.
  class Search
    LIMIT = 500

    Row = Data.define(:kind, :record, :title, :date, :subtag, :interview, :snippet, :rank)

    def self.call(tag:, filter:)
      return [] unless tag

      new(tag:, filter:).call
    end

    def initialize(tag:, filter:)
      @tag = tag
      @filter = filter
    end

    def call
      rows = [] # : Array[Row]
      rows.concat(email_rows) if @filter.include_emails?
      rows.concat(document_rows) if @filter.include_documents?
      (ranked? ? rows.sort_by { |row| row.rank.to_f } : rows.sort_by(&:date).reverse).first(LIMIT)
    end

    private

    def ranked?
      @filter.query.present? && !(@filter.include_emails? && @filter.include_documents?)
    end

    def email_rows
      emails = Email.preload(:interview, taggings: :subtag).where(id: tagged_ids("Email")).where(date: date_range)
      records(emails).map do |email, snippet, rank|
        Row.new(kind: :email, record: email, title: email.subject.to_s, date: email.date, subtag: subtag_of(email),
                interview: email.interview, snippet:, rank:) # steep:ignore
      end
    end

    def document_rows
      documents = Document.preload({ email: :interview }, taggings: :subtag).where(id: tagged_ids("Document"))
                          .where(created_at: date_range)
      records(documents).map do |document, snippet, rank|
        Row.new(kind: :document, record: document, title: document.title, date: document.created_at,
                subtag: subtag_of(document), interview: document.email&.interview, snippet:, rank:) # steep:ignore
      end
    end

    # [record, snippet, rank] triples; FTS matches when there is a query, else newest first.
    def records(relation)
      if @filter.query
        relation.fts_search(@filter.query, limit: LIMIT).map { |match| [ match.record, match.snippet, match.rank ] } # steep:ignore
      else
        relation.order(date_column(relation) => :desc).limit(LIMIT).map { |record| [ record, nil, nil ] }
      end
    end

    def date_column(relation)
      relation.klass == Email ? :date : :created_at
    end

    def tagged_ids(type)
      taggings = Tagging.where(taggable_type: type, tag_id: @tag.id)
      taggings = taggings.where(subtag_id: subtag_ids) if @filter.subtag_name
      taggings.select(:taggable_id)
    end

    def subtag_ids
      @tag.subtags.where(name: @filter.subtag_name).select(:id)
    end

    def date_range
      from = @filter.from_date.in_time_zone.beginning_of_day
      to = @filter.to_date&.in_time_zone&.end_of_day
      from..to
    end

    def subtag_of(record)
      record.taggings.to_a.find { |tagging| tagging.tag_id == @tag.id }&.subtag
    end
  end
end
