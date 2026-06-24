class ApplicationMail < ApplicationRecord
  include Searchable
  COLUMN_NAMES = %w[id date provider email_id company job_title action].freeze

  def self.tool_column_names = COLUMN_NAMES

  validates :date, :provider, :email_id, presence: true
  validates :email_id, uniqueness: true

  # rubocop:disable Metrics/BlockLength
  scope :groupped, -> {
    group(:company, :job_title).select(<<~SQL)
      company,
      job_title,
      json_group_array(id ORDER BY date ASC) AS mail_ids,
      json_group_array(date ORDER BY date ASC) AS mail_dates,
      json_group_array(action ORDER BY date ASC) AS actions
    SQL
  }
  # rubocop:enable Metrics/BlockLength

  # Returns all records as an array of plain hashes (for tool responses).
  def self.as_rows(scope = all)
    scope.order(:date).map do |r|
      COLUMN_NAMES.index_with { |col| r.public_send(col)&.to_s } # steep:ignore
    end
  end
end
