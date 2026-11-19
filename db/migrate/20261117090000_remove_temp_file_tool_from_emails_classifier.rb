# GH #299: EmailsClassifier reads untrusted subject lines and never needs scratch files, so Records::TempFileTool is
# taken off it (db/seeds.rb and the agent class already omit it). Data-only; other agents keep their tools.
class RemoveTempFileToolFromEmailsClassifier < ActiveRecord::Migration[8.1]
  AGENT_NAME = "Orchestration::Agents::EmailsClassifier".freeze
  TOOL       = "Records::TempFileTool".freeze

  class MigrationAgent < ActiveRecord::Base
    self.table_name = "orchestration_agents"
    self.inheritance_column = nil
  end

  def up
    MigrationAgent.where(name: AGENT_NAME).find_each do |agent|
      tools = agent.tools
      next unless tools.is_a?(Array) && tools.include?(TOOL)

      agent.update_columns(tools: tools - [ TOOL ])
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
