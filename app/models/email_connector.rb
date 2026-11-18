class EmailConnector < ApplicationRecord
  # Configuration keys each provider may store. Gmail keeps none: its OAuth paths are server config.
  ALLOWED_CONFIGURATION = {
    Emails::GMAIL => [], #: Array[String]
    Emails::YAHOO => %w[username password]
  }.freeze

  serialize :configuration, type: Hash, coder: JSON
  encrypts :configuration

  before_validation :normalize_configuration

  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: Emails::PROVIDER_NAMES }

  private

  # Merges the submitted keys into the stored configuration (a blank password keeps the stored one) and drops
  # every key the provider does not allow, including stale ones left by a provider change.
  def normalize_configuration
    submitted = configuration.to_h.deep_stringify_keys
    submitted.delete("password") if submitted["password"].blank?

    self.configuration = stored_configuration.merge(submitted).slice(*ALLOWED_CONFIGURATION.fetch(provider, []))
  end

  def stored_configuration
    return {} if new_record? || provider_changed?

    configuration_in_database.to_h.deep_stringify_keys
  end
end
