# ExperimentsController is too long

**Status:** draft

**Source:** `app/controllers/evaluation/experiments_controller.rb`

`Evaluation::ExperimentsController` handles the full experiment lifecycle (index, show, new/create with a wizard, improve, compare, activate, status polling, metric results, destroy). The breadth requires a `rubocop:disable Metrics/ClassLength` suppression and makes the controller hard to navigate.

**Suggested approach:** extract the multi-step wizard logic into a form/command object and move non-RESTful orchestration steps to dedicated service objects, in line with the thin-controller rule in `.claude/rules/controllers.md`.
