todo "archspec_todo.yml"

# Association targets, custom validators and conditional concern effects are
# resolved by Rails at runtime; `archspec reflect` captures them into
# archspec_facts/ (committed, so CI checks without booting the app).
reflect :rails

# Layers are ordered: a layer may depend on itself and on layers below it.
architecture :layered, layers: {
  interface:   %w[app/controllers/**/*.rb app/components/**/*.rb app/helpers/**/*.rb],
  application: %w[app/services/**/*.rb app/forms/**/*.rb app/jobs/**/*.rb
                  lib/orchestration/**/*.rb lib/evaluation/**/*.rb lib/tasks/**/*.rake],
  tools:       "app/tools/**/*.rb",
  domain:      "app/models/**/*.rb",
  infra:       %w[lib/emails/**/*.rb lib/embeddings/**/*.rb]
}
architecture :ruby_conventions

# Layers cannot separate sibling subsystems, so add component rules.
component(:evaluation, in: %w[lib/evaluation/**/*.rb app/models/evaluation/**/*.rb
                              app/services/evaluation/**/*.rb])
component(:orchestration, in: %w[lib/orchestration/**/*.rb app/models/orchestration/**/*.rb])
  .cannot_use(:evaluation)

# Don't admit :orchestration/:evaluation in the layer allowlists: since archspec
# 1.2, a target passes when any component that owns it is allowed, so that would
# let every layer reach the subsystems' application-layer files.
