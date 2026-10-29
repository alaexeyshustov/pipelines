require_relative "support/agent_evaluation"

module Evaluation
  module Regression
    class EmailsClassifierEvaluation < AgentEvaluation
      agent Orchestration::Agents::EmailsClassifier

      golden [
        { input: { emails: [ { id: "m1", subject: "Your application for Senior Ruby Engineer at Acme" } ] } },
        { input: { emails: [ { id: "m2", subject: "Interview invitation: Backend Developer, Globex" },
                             { id: "m3", subject: "Weekly newsletter: 10 gardening tips" } ] } },
        { input: { emails: [ { id: "m4", subject: "Offer letter - Staff Engineer" } ] } }
      ]

      evaluation :covers_every_email,
                 "Every email id from the input appears exactly once in the output results.", minimum: 0.8
      evaluation :tags_fit_subject,
                 "Each email has short, lowercase tags that describe its subject; job-related emails get " \
                 "job-related tags (for example job, application, interview, offer).", minimum: 0.7
    end
  end
end
