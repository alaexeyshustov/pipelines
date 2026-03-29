class Interview < ApplicationRecord
  include Searchable
  validates :company, :job_title, presence: true
  validates :job_title, uniqueness: { scope: :company }

  STATUSES = %w[pending_reply having_interviews rejected offer_received].freeze
  COLUMN_NAMES = %w[
    id company job_title status applied_at rejected_at
    first_interview_at second_interview_at third_interview_at fourth_interview_at
  ].freeze

  # Returns all records as plain hashes (for tool responses).
  def self.as_rows(scope = all)
    scope.order(:company, :job_title).map do |r|
      COLUMN_NAMES.index_with { |col| r.public_send(col)&.to_s }
    end
  end
end
