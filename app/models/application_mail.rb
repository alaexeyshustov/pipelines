class ApplicationMail < ApplicationRecord
  validates :date, :provider, :email_id, presence: true
  validates :email_id, uniqueness: true

  COLUMN_NAMES = %w[date provider email_id company job_title action].freeze

  # Returns all records as an array of plain hashes (for tool responses).
  def self.as_rows(scope = all)
    scope.order(:date).map do |r|
      COLUMN_NAMES.index_with { |col| r.public_send(col)&.to_s }
    end
  end
end
