# ADR 0018: Email tools are scoped to messages listed in the chat

## Status
Accepted (GH #303; resolves SEC-07 in #240)

## Context

#299 added provider validation, hashed cache names and a label denylist to `Emails::GetTool` and `Emails::AddLabelsTool`, but left scoping out. A prompt-injected agent could still read or relabel any message by guessing ids (sequential IMAP UIDs, other folders).

## Decision

- **Per-chat allowlist.** Only messages that `Emails::ListTool` or `Emails::SearchTool` returned earlier in the same agent chat are accepted by `GetTool` and `AddLabelsTool`. An id outside it returns `{ error: }` without calling the provider; the text tells the model to list or search first. Chats are not resumed across jobs, so a retry starts with an empty scope.
- **`Emails::MessageScope`** (plain Ruby, `app/tools/emails/message_scope.rb`) offers `record(messages)`, `allow?(provider:, message_id:, mailbox: nil)` and `bind(tool_classes)`. Its key set is guarded by a `Mutex`.
- **Binding in the builder.** `Orchestration::RuntimeAgentBuilder#apply_tools` calls `Emails::MessageScope.new.bind(tools)` once per build. `bind` instantiates only classes that answer `message_scoped?` (the four email tools above) with `new(message_scope: scope)`; other classes pass through. `policy.tools` stays classes, so the `ActionExecutor` snapshot is unchanged. Both the run path and evaluation sampling go through the builder.
- **Key.** Yahoo: `(provider, mailbox, id)`, because UIDs are unique per mailbox only. The mailbox is the message's `labels.first`, matched case-insensitively; blank means `INBOX`. Gmail: `(provider, id)`. Ids match as exact strings, so `"<validity>:<uid>"` and `"42abc"` are refused. Nil ids and non-hash items are not recorded. The provider comes from each message's own `provider` field.
- **Fail closed.** The tools default to `message_scope: Emails::MessageScope.new` (empty), so any path that builds them without the builder refuses every id.
- **Sampling.** The write-blocked `AddLabelsTool` subclass in `Evaluation::Sampler` inherits the constructor and still returns its sentinel first.
- **No data migration.** The legacy agent rows (`EmailsMapper`, `RecordsStorer`, `RecordsFiller`) are left as they are; see Consequences.

## Consequences

- Agents must call a listing tool before `get_email` or `add_labels`. User agents (and eval datasets) that pass ids in their input get refusals.
- The scope stops guessed ids and ids taken from the input. It does not confine folders: an agent with `ListTool` or `SearchTool` can list any label or mailbox (`list_emails(label: "Archive")`, `search_emails(query: "from:bank")`) and then read or relabel what it got back.
- Sampling `GetTool` reads are narrowed to listed ids, which amends [ADR 0008](0008-sampler-real-tool-calls-with-write-blocking.md).
- Older databases still have migration-seeded agents whose prompts call `get_email` on ids from the step input, without a listing tool: `EmailsMapper` (`GetTool`), `RecordsStorer` (`GetTool`, `AddLabelsTool`) and `RecordsFiller` (`GetTool`). Their calls are now refused. Their tools, prompts and `enabled` flag are unchanged; a user who still needs one adds `ListTool`/`SearchTool` to it or removes the email tools in the agent UI.
- If a listing and a `get_email` run in the same concurrent round, the `get_email` may be refused. It fails closed.
