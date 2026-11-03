class Tag < ApplicationRecord
  NAMES = %w[medical job_application child subscription bureaucracy finance].freeze

  STARTER_SUBTAGS = {
    "medical"         => %w[appointment lab_result prescription insurance_claim referral],
    "job_application" => %w[application_sent rejection interview_invite offer recruiter_outreach],
    "child"           => %w[school kindergarten activities health documents],
    "subscription"    => %w[renewal invoice cancellation price_change trial],
    "bureaucracy"     => %w[residence_permit tax_office registration municipality official_letter],
    "finance"         => %w[bank invoice tax insurance salary]
  }.freeze

  has_many :subtags, dependent: :destroy
  has_many :taggings, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  # Idempotent: creates the fixed tags and starter subtags if missing.
  def self.seed_defaults!
    transaction do
      STARTER_SUBTAGS.each do |name, subtag_names|
        tag = find_or_create_by!(name:)
        subtag_names.each { |subtag_name| tag.subtags.find_or_create_by!(name: subtag_name) }
      end
    end
  end
end
