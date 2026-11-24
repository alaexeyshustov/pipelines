# Adds polymorphic tagging (see +Tagging+); taggings are removed with the record. The including table has a string
# +classification_status+ column: pending (never classified), tagged (has any tagging, manual ones included), untagged
# (classified, nothing assigned) or failed (the last classification raised). A plain enum, not AASM: forcing a
# reclassification and a changed Drive file move a record between any two states. Tags::Classify sets it.
module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings

    enum :classification_status, { pending: "pending", tagged: "tagged", untagged: "untagged", failed: "failed" },
         default: :pending, validate: true

    # Records still to classify (pending or failed) that were stored before +before+.
    scope :awaiting_tagging, ->(before:) { where(classification_status: %w[pending failed]).where(created_at: ...before) }
  end
end
