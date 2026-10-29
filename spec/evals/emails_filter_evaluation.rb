require_relative "support/agent_evaluation"

module Evaluation
  module Regression
    class EmailsFilterEvaluation < AgentEvaluation
      agent Orchestration::Agents::EmailsFilter

      golden [
        { input: { topic: "job applications",
                   emails: [ { id: "m1", subject: "Interview invitation", tags: %w[job interview] },
                             { id: "m2", subject: "Garden newsletter", tags: %w[newsletter garden] } ] } },
        { input: { topic: "job applications",
                   emails: [ { id: "m3", subject: "Weekly deals", tags: %w[promo shopping] } ] } },
        { input: { topic: "job applications",
                   emails: [ { id: "m4", subject: "Offer letter", tags: %w[job offer] },
                             { id: "m5", subject: "Application received", tags: %w[application job] } ] } }
      ]

      evaluation :keeps_only_topic_emails,
                 "Only emails whose tags relate to the topic are returned; unrelated emails are dropped.",
                 minimum: 0.8
      evaluation :returns_valid_results,
                 "The output is a results list of objects with id and tags, or an empty list when nothing matches.",
                 minimum: 0.7
    end
  end
end
