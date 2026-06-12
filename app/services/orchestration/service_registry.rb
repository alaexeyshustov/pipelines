module Orchestration
  module ServiceRegistry
    REGISTRY = {
      "Emails::FetchExecutor"            => Emails::FetchExecutor,
      "Orchestration::IngestionExecutor" => Orchestration::IngestionExecutor,
      "Orchestration::QueryExecutor"     => Orchestration::QueryExecutor,
      "Interviews::GistExportExecutor"   => Interviews::GistExportExecutor
    }.freeze # : Hash[String, _AgentCallable]

    def self.lookup(name)
      REGISTRY[name] if name
    end
  end
end
