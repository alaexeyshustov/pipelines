module Orchestration
  module ServiceRegistry
    REGISTRY = {
      "Orchestration::Executors::EmailsFetcher"          => Orchestration::Executors::EmailsFetcher,
      "Orchestration::Executors::Ingestion"              => Orchestration::Executors::Ingestion,
      "Orchestration::Executors::Query"                  => Orchestration::Executors::Query,
      "Orchestration::Executors::InterviewsGistExporter" => Orchestration::Executors::InterviewsGistExporter,
      "Orchestration::Executors::DriveDocumentsSync"     => Orchestration::Executors::DriveDocumentsSync,
      "Orchestration::Executors::EmailsList"             => Orchestration::Executors::EmailsList,
      "Orchestration::Executors::EmailsClassify"         => Orchestration::Executors::EmailsClassify,
      "Orchestration::Executors::EmailsEmbed"            => Orchestration::Executors::EmailsEmbed,
      "Orchestration::Executors::AttachmentsIngest"      => Orchestration::Executors::AttachmentsIngest,
      "Orchestration::Executors::DocumentsClassify"      => Orchestration::Executors::DocumentsClassify,
      "Orchestration::Executors::DocumentsEmbed"         => Orchestration::Executors::DocumentsEmbed
    }.freeze # : Hash[String, _AgentCallable]

    def self.lookup(name)
      REGISTRY[name] if name
    end
  end
end
