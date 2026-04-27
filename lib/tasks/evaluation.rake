namespace :evaluation do
  desc "Migrate hardcoded agent instructions into Leva::Prompt records"
  task migrate_prompts: :environment do
    agent_classes = %w[
      Emails::ClassifyAgent
      Emails::FilterAgent
      Emails::MappingAgent
      Records::FillAgent
      Records::NormalizeAgent
      Records::StoreAgent
      Records::ReconcileAgent
    ].freeze

    agent_classes.each do |agent_class|
      klass = agent_class.constantize
      raise "#{agent_class} has no instructions" if klass.instructions.blank?

      Leva::Prompt.find_or_initialize_by(name: agent_class).tap do |prompt|
        prompt.system_prompt = klass.instructions
        # user_prompt is intentionally preserved on re-runs to avoid clobbering manual edits
        prompt.user_prompt = prompt.user_prompt.presence || "{{input}}"
        prompt.save!
      end
    end
    Rails.logger.info "Migrated #{agent_classes.size} agent prompts to Leva::Prompt."
  end
end
