class EmailConnector < ApplicationRecord
  serialize :configuration, type: Hash, coder: JSON

  before_save :convert_configuration_to_hash

  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: %w[gmail yahoo] }

  private

  def convert_configuration_to_hash
    self.configuration = configuration.to_h.deep_transform_keys(&:to_s).to_h if configuration.respond_to?(:to_h)
  end
end
