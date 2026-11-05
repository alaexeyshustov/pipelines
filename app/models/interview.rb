class Interview < ApplicationRecord
  include Searchable
  include Batchable
  has_many :emails, dependent: :nullify

  validates :company, :job_title, presence: true
  validates :job_title, uniqueness: { scope: :company }

  STATUSES = %w[pending_reply having_interviews rejected offer_received].freeze
  COLUMN_NAMES = %w[
    id company job_title status applied_at rejected_at
    first_interview_at second_interview_at third_interview_at fourth_interview_at
  ].freeze

  # Gender markers job ads append to titles: "(m/w/d)", "(f/m/x)", "- m/w/d", "(all genders)", "(gn)".
  GENDER_MARKER = %r{
    \s*[(\[]\s*(?:[mwfdxi]\s*/\s*){1,2}[mwfdxi][*+]?\s*[)\]]
    | \s*[(\[]\s*(?:all\s+genders?|alle\s+geschlechter|gn)\s*[)\]]
    | (?<![\w/])(?:[mwfdxi]/){1,2}[mwfdxi](?![\w/])
  }xi
  TRAILING_GROUP = /\s*[(\[][^()\[\]]*[)\]]\s*\z/
  TRAILING_SEPARATORS = /[\s\-\u2013\u2014,:|]+\z/

  # Company and job title as the LLM reports them vary ("Backend Engineer (m/w/d)" vs "Backend Engineer"), which
  # would split one application into several Interviews. This drops gender markers and trailing parenthesised or
  # bracketed groups, trims dangling separators and squishes whitespace. A value that would become empty (for
  # example "(Remote)") is only squished.
  def self.normalize_name(value)
    squished = value.to_s.squish
    name = squished.gsub(GENDER_MARKER, " ")
    name = name.sub(TRAILING_GROUP, "") while name.match?(TRAILING_GROUP)
    name = name.sub(TRAILING_SEPARATORS, "").squish
    name.empty? ? squished : name
  end

  def self.tool_column_names = COLUMN_NAMES

  def self.as_rows(scope = all)
    scope.order(:company, :job_title).map do |r|
      COLUMN_NAMES.index_with { |col| r.public_send(col)&.to_s } # steep:ignore
    end
  end
end
