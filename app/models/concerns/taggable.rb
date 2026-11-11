# Adds polymorphic tagging (see +Tagging+); taggings are removed with the record. The including table has a
# +tagged_at+ column, set once Tags::Classifier succeeded (NULL = untagged backlog).
module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings

    # Records whose tagging has not completed (tagged_at NULL) that were stored before +before+.
    scope :awaiting_tagging, ->(before:) { where(tagged_at: nil).where(created_at: ...before) }
  end
end
