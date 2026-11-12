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

  DEFAULT_THRESHOLD = 0.35

  has_many :subtags, dependent: :destroy
  has_many :taggings, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  # Minimum probability for Tags::Classifier to keep a tag: Setting "tagging_threshold", then ENV TAGGING_THRESHOLD,
  # then 0.35.
  def self.threshold
    Float(Setting.fetch("tagging_threshold") || ENV.fetch("TAGGING_THRESHOLD", DEFAULT_THRESHOLD))
  end

  # Idempotent: creates the fixed tags and starter subtags if missing.
  def self.seed_defaults!
    transaction do
      tags = where(name: STARTER_SUBTAGS.keys).index_by(&:name)
      known = Subtag.where(tag_id: tags.values.map(&:id)).pluck(:tag_id, :name).to_set
      STARTER_SUBTAGS.each do |name, subtag_names|
        tag = tags[name] ||= create!(name:)
        seed_subtags(tag, subtag_names, known)
      end
    end
  end

  def self.seed_subtags(tag, names, known)
    names.each { |name| tag.subtags.create!(name:) unless known.include?([ tag.id, name ]) }
  end
  private_class_method :seed_subtags
end
