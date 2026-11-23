class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true

  # Creates the user, or sets a new password on the existing one (the task behind `bin/rails users:upsert`).
  def self.upsert_login!(email_address:, password:)
    find_or_initialize_by(email_address:).tap do |user|
      user.password = password
      # has_secure_password ignores a blank password on an existing record, which would leave the old one in place silently.
      user.errors.add(:password, :blank) if password.blank?
      raise ActiveRecord::RecordInvalid, user if user.errors.any?

      user.save!
    end
  end
end
