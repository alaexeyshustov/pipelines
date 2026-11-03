# Adds polymorphic tagging (see +Tagging+); taggings are removed with the record.
module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings
  end
end
