class Subtag < ApplicationRecord
  belongs_to :tag
  has_many :taggings, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :tag_id }
end
