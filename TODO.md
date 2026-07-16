# features

[-] Models balancer
[-] auto remove old chats
[ ] cli pipeline runner switch to run job inline
[ ] pipeline for ocr
[ ] pipeline for emails
[x] agents - json input better schema UI
[ ] actions - split the view for agents and services
[x] CI pipeline: add bundle audit and pnpm audit steps
[ ] pipeline: option to run a single step
[x] pipeline: add output schema
[ ] navigation: clicking bug
[x] evaluation: add option to create a new prompt version from an agent
[x] evaluation: add button to resync dataset from chats
[ ] evaluation: move to a separate nav item
[ ] evaluation: list prompt versions add some hints
[x] evaluation: use model searchable select
[x] evaluation: issue running
[x] evaluation: show dataset in experiment view
[ ] evaluation: prompt improvement service
[x] navigation: add jobs nav item
[ ] evaluation: create test tasks to evaluate agents (new app, refactoring, bug fixing)
[ ] orchestration: remove params from step_actions, move to the mapping
[ ] jobs: update state if failed
[ ] jobs: check resumable
[x] refactoring: stricter rubocop rules: class length, method length, cyclomatic complexity
[x] refactoring: save repeated queries to models
[x] refactoring: extract all pure function to lib/{domain} (json, jsonschema etc.)
[ ] refactoring: move all orchestration agents and services to lib/orchestration
[x] refactoring: long classes - find pure functions and extract to helpers
[ ] refactoring: decouple orchestration from evaluation, move orchestration to lib/
[ ] refactoring: deduplicate tests
[ ] refactoring: tests - extract factories, stubbs and mocks in let and before
[ ] refactoring: tests - extract methods to let and before
[ ] refactoring: tests - extract long hashes into let
[ ] upgrade: rubyllm new version
[ ] improve: add git hook to tun specs, cops and steep check on modified files
