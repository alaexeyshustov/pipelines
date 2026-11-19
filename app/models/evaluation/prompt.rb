module Evaluation
  class Prompt < ApplicationRecord
    self.table_name = "evaluation_prompts"

    has_many :experiments, class_name: "Evaluation::Experiment", dependent: :nullify
    has_many :samples, class_name: "Evaluation::Sample", dependent: :nullify

    validates :name, presence: true
    validates :user_prompt, presence: true

    before_validation :assign_next_version, on: :create

    scope :versions_for, ->(name) { where(name:).order(version: :desc) }
    scope :active, -> { where(active: true) }

    def self.active_for_agent(agent_name) = active.find_by(name: agent_name)

    def self.latest_for_agent(agent_name)
      where(name: agent_name).order(version: :desc, id: :desc).first
    end

    # The system prompt a run uses: the activated version, else the agent's own prompt.
    def self.effective_system_prompt_for(agent_name)
      active_for_agent(agent_name)&.system_prompt || agent_default_for(agent_name)
    end

    def self.agent_default_for(name) = Orchestration::Agent.named(name)&.prompt

    def self.metadata_versions_for(name) = versions_for(name).select(:id, :version, :active)

    def self.other_versions_for(name, excluding_id:) = where(name:).where.not(id: excluding_id).order(version: :desc, id: :desc)

    def activate!
      self.class.transaction do
        self.class.where(name:).where.not(id:).update_all(active: false)
        update!(active: true, activated_at: Time.current)
      end
    end

    def deactivate!
      update!(active: false) if active?
    end

    # A version may go live once it has a completed experiment or was live before.
    def activatable? = activated_at.present? || experiments.exists?(status: :completed)

    def label = "v#{version}"

    private

    def assign_next_version
      return if version.present?

      self.version = self.class.where(name: name).maximum(:version).to_i + 1
    end
  end
end
