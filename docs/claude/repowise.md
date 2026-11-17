# repowise (git-history context)

The `repowise` MCP server (`.mcp.json`) answers from a per-machine index in `.repowise/`. Build it once with `mise run repowise:init`; `.husky/post-commit` refreshes it in the background. Without an index the tools return nothing.

- Before finishing a multi-file change, call `get_risk(changed_files=[...])` and read `directive.missing_cochanges` for companions the diff is missing: RBS sigs under `sig/`, specs, forms, components. Ignore `tests_to_run`: the graph has no edges from RSpec files, so it falls back to every test.
- Empty caller lists are not proof of dead code. repowise resolves Ruby constants only under `app/{models,controllers,services,jobs,mailers,helpers,channels,policies}` and `lib`, so callers of `app/components`, `app/forms`, `app/tools` and `app/schemas` are missing. Use rubydex or grep there.
- `get_risk` size scores are a PR-size percentile, not a bug predictor. Treat them as advisory.
