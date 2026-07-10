module Evaluation
  class Prompt < ApplicationRecord
    self.table_name = "evaluation_prompts"

    include Evaluation::AutoEvalTriggerable

    has_many :experiments, class_name: "Evaluation::Experiment", dependent: :nullify
    has_many :samples, class_name: "Evaluation::Sample", dependent: :nullify

    validates :name, presence: true
    validates :user_prompt, presence: true

    before_validation :assign_next_version, on: :create

    scope :versions_for, ->(name) { where(name:).order(version: :desc) }
    scope :active_metadata_versions_for, ->(agent_names) { where(name: agent_names).where("json_extract(metadata, '$.active') = ?", true) }

    def self.last_for_agent(agent_name)
      where(name: agent_name).order(version: :desc, id: :desc).first
    end

    def self.metadata_versions_for(name) = versions_for(name).select(:id, :version, :metadata)

    def self.other_versions_for(name, excluding_id:) = where(name:).where.not(id: excluding_id).order(version: :desc, id: :desc)

    private

    def assign_next_version
      return if version.present?

      self.version = self.class.where(name: name).maximum(:version).to_i + 1
    end
  end
end
