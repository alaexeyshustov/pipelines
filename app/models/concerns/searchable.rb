# frozen_string_literal: true

module Searchable
  extend ActiveSupport::Concern

  included do
    scope :search, ->(q) {
      next all if q.blank?

      pattern = "%#{sanitize_sql_like(q)}%"
      where("company LIKE ? OR job_title LIKE ?", pattern, pattern)
    }
  end
end
