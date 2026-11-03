# N+1 query gate (GH #212): every example is scanned, and an N+1 query fails
# it with Prosopite::NPlusOneQueriesError. The pre-commit hook and CI enforce
# this through their existing rspec runs.
#
# To allow an intentional N+1, add a pattern below with a one-line reason.
# Stack patterns match a call-stack frame, e.g. "app/x.rb:12:in 'X#y'"; scope
# them to a method rather than a whole file. Spec files whose subject is
# inherently per-record (seeds, one-off scripts) opt out with `prosopite: false`.
Prosopite.raise = true
Prosopite.rails_logger = false

# Setup queries are not the code under test.
Prosopite.pause_during("factory_bot.run_factory")

Prosopite.ignore_queries = [
  # RubyLLM resolves each chat's model from its registry inside the gem.
  /FROM "ruby_llm_models"/
]

Prosopite.allow_stack_paths = [
  # Steps run in sequence, each needing the previous step's outputs.
  /PipelineRunner#reload_action_runs/,
  # Each action gets its own chat; RubyLLM loads it when instructions are set.
  /RuntimeAgentBuilder#apply_prompt/,
  # One lookup per agent in a step; the resolver caches it for the run.
  /ActivePromptResolver#call/,
  # One message query per sampled run, bounded by sample_size.
  /ToolCallExtractor\.call/,
  # destroy_all runs each record's dependent: :destroy callbacks.
  /Batchable::ClassMethods#destroy_by_ids/,
  # A rare admin action over a small file; lookups per imported record.
  /PipelineImporter#import_pipeline/,
  # Reads one setting per model role while the agent classes load.
  /LlmModels\./
]

RSpec.configure do |config|
  config.before do |example|
    Prosopite.scan(example.location) unless example.metadata[:prosopite] == false
  end

  config.after { Prosopite.finish }
end
