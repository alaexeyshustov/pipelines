module Orchestration
  module ServiceRegistry
    REGISTRY = {
      "Orchestration::Executors::EmailsFetcher"          => Orchestration::Executors::EmailsFetcher,
      "Orchestration::Executors::Ingestion"              => Orchestration::Executors::Ingestion,
      "Orchestration::Executors::Query"                  => Orchestration::Executors::Query,
      "Orchestration::Executors::InterviewsGistExporter" => Orchestration::Executors::InterviewsGistExporter
    }.freeze # : Hash[String, _AgentCallable]

    def self.lookup(name)
      REGISTRY[name] if name
    end
  end
end
