# frozen_string_literal: true

class RenameOrchestrationAgentAndExecutorClasses < ActiveRecord::Migration[8.1]
  AGENT_RENAMES = {
    "Emails::ClassifyAgent"   => "Orchestration::Agents::EmailsClassifier",
    "Emails::FilterAgent"     => "Orchestration::Agents::EmailsFilter",
    "Emails::MappingAgent"    => "Orchestration::Agents::EmailsMapper",
    "Records::FillAgent"      => "Orchestration::Agents::RecordsFiller",
    "Records::NormalizeAgent" => "Orchestration::Agents::RecordsNormalizer",
    "Records::ReconcileAgent" => "Orchestration::Agents::RecordsReconciler",
    "Records::StoreAgent"     => "Orchestration::Agents::RecordsStorer"
  }.freeze

  EXECUTOR_RENAMES = {
    "Emails::FetchExecutor"            => "Orchestration::Executors::EmailsFetcher",
    "Orchestration::IngestionExecutor" => "Orchestration::Executors::Ingestion",
    "Orchestration::QueryExecutor"     => "Orchestration::Executors::Query",
    "Interviews::GistExportExecutor"   => "Orchestration::Executors::InterviewsGistExporter"
  }.freeze

  def up
    AGENT_RENAMES.each do |old_name, new_name|
      execute("UPDATE orchestration_agents SET name = #{quote(new_name)} WHERE name = #{quote(old_name)}")
      execute("UPDATE evaluation_prompts SET name = #{quote(new_name)} WHERE name = #{quote(old_name)}")
      execute("UPDATE evaluation_metrics SET agent_name = #{quote(new_name)} WHERE agent_name = #{quote(old_name)}")
      execute("UPDATE evaluation_datasets SET agent_name = #{quote(new_name)} WHERE agent_name = #{quote(old_name)}")
    end

    EXECUTOR_RENAMES.each do |old_class, new_class|
      execute("UPDATE orchestration_actions SET agent_class = #{quote(new_class)} WHERE agent_class = #{quote(old_class)}")
    end
  end

  def down
    AGENT_RENAMES.each do |old_name, new_name|
      execute("UPDATE orchestration_agents SET name = #{quote(old_name)} WHERE name = #{quote(new_name)}")
      execute("UPDATE evaluation_prompts SET name = #{quote(old_name)} WHERE name = #{quote(new_name)}")
      execute("UPDATE evaluation_metrics SET agent_name = #{quote(old_name)} WHERE agent_name = #{quote(new_name)}")
      execute("UPDATE evaluation_datasets SET agent_name = #{quote(old_name)} WHERE agent_name = #{quote(new_name)}")
    end

    EXECUTOR_RENAMES.each do |old_class, new_class|
      execute("UPDATE orchestration_actions SET agent_class = #{quote(old_class)} WHERE agent_class = #{quote(new_class)}")
    end
  end
end
