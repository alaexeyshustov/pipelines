todo "archspec_todo.yml"

# Layers are ordered: a layer may depend on itself and on layers below it.
architecture :layered, layers: {
  interface:   %w[app/controllers/**/*.rb app/components/**/*.rb app/helpers/**/*.rb],
  application: %w[app/services/**/*.rb app/forms/**/*.rb app/jobs/**/*.rb
                  lib/orchestration/**/*.rb lib/evaluation/**/*.rb lib/pipeline/**/*.rb],
  tools:       "app/tools/**/*.rb",
  domain:      "app/models/**/*.rb",
  infra:       "lib/emails/**/*.rb"
}
architecture :ruby_conventions

# Layers cannot separate sibling subsystems, so add component rules.
component(:evaluation, in: %w[lib/evaluation/**/*.rb app/models/evaluation/**/*.rb
                              app/services/evaluation/**/*.rb])
component(:orchestration, in: %w[lib/orchestration/**/*.rb app/models/orchestration/**/*.rb])
  .cannot_use(:evaluation)

# Subsystem components overlap the layers, so every layer's allowlist must also
# admit them as targets (rules for the same source merge).
interface.can_only_use :orchestration, :evaluation
application.can_only_use :orchestration, :evaluation
tools.can_only_use :orchestration, :evaluation
domain.can_only_use :orchestration, :evaluation
infra.can_only_use :orchestration, :evaluation
