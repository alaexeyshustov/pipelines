namespace :evaluation do
  AGENT_CLASSES = %w[
    Emails::ClassifyAgent
    Emails::FilterAgent
    Emails::MappingAgent
    Records::FillAgent
    Records::NormalizeAgent
    Records::StoreAgent
    Records::ReconcileAgent
  ].freeze

  desc "Migrate hardcoded agent instructions into Leva::Prompt records"
  task migrate_prompts: :environment do
    AGENT_CLASSES.each do |agent_class|
      klass = agent_class.constantize
      Leva::Prompt.find_or_initialize_by(name: agent_class).tap do |prompt|
        prompt.system_prompt = klass.instructions
        prompt.user_prompt = prompt.user_prompt.presence || "{{input}}"
        prompt.save!
      end
    end
    puts "Migrated #{AGENT_CLASSES.size} agent prompts to Leva::Prompt."
  end
end
