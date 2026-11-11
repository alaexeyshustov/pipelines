class Tagging < ApplicationRecord
  SOURCES = %w[llm manual].freeze

  belongs_to :taggable, polymorphic: true
  belongs_to :tag
  belongs_to :subtag, optional: true

  scope :manual, -> { where(source: "manual") }

  validates :source, inclusion: { in: SOURCES }
  validates :tag_id, uniqueness: { scope: %i[taggable_type taggable_id] }
  validate :subtag_belongs_to_tag

  private

  def subtag_belongs_to_tag
    return if subtag.nil? || subtag.tag_id == tag_id

    errors.add(:subtag, "must belong to the selected tag")
  end
end
