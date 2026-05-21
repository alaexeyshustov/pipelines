---
status: proposed
---

# PRD: Name the IMAP Adapter Seam

## Summary

Extract all IMAP-generic logic from `YahooAdapter` into a new `Emails::Adapters::ImapAdapter`. The intermediate class sits between `BaseAdapter` and IMAP-based connectors. `YahooAdapter` shrinks to two methods: `from_env` and `self.setup`. Adding a third IMAP connector requires only those two methods plus a new class file.

## Problem

`YahooAdapter` owns ~200 lines of standard IMAP mechanics — connection management, search criteria building, UID pagination, body parsing, label/mailbox operations — that are not Yahoo-specific. `BaseAdapter` defines the contract for all providers but captures no shared IMAP behaviour. The seam between "IMAP protocol" and "provider-specific credentials" is unnamed and invisible.

Three consequences:

- **No shared IMAP home.** The next IMAP connector (Fastmail, Outlook) must re-implement `with_lock`, `ensure_mailbox`, UID pagination, and all seven interface methods from scratch.
- **Inflated `YahooAdapter`.** ~200 lines of IMAP mechanics alongside two lines of Yahoo-specific code, with no structural distinction between them.
- **Spec duplication risk.** Workflow coverage is tied to `YahooAdapter`; a second IMAP connector would re-test the same mechanics.

## Goals

- Extract IMAP-generic logic into `Emails::Adapters::ImapAdapter`.
- Slim `YahooAdapter` to exactly two methods: `from_env` and `self.setup`.
- Make adding a third IMAP connector mean: one new class file with `from_env` and `self.setup`.

## Non-Goals

- Changing the seven-method public interface defined in `BaseAdapter`.
- Changing `GmailAdapter` — it stays on `BaseAdapter` directly (Google REST API, not IMAP).
- Adding OAuth IMAP support — the `imap` private method can be overridden by a subclass when needed.
- Changing `ImapSearchCriteria` or `ImapBodyParser`.
- Changing the controller or any call sites — the public interface is unchanged.

## Primary Users

- Developers adding a new IMAP-based email connector.
- Developers reading or changing IMAP behaviour (search, pagination, label management).

## Functional Requirements

### 1. Class hierarchy

```
BaseAdapter
├── GmailAdapter        (unchanged)
└── ImapAdapter         (new)
    └── YahooAdapter    (slimmed)
```

### 2. ImapAdapter owns all IMAP-generic behaviour

`ImapAdapter` inherits from `BaseAdapter` and implements all seven interface methods concretely using standard IMAP operations:

| Method | IMAP mechanism |
|--------|---------------|
| `search_messages` | `ImapSearchCriteria` → `uid_search` → array-slice pagination |
| `list_messages` | `ImapSearchCriteria` → `uid_search` → array-slice pagination |
| `get_message` | `uid_fetch` → `ImapBodyParser` |
| `get_labels` | `imap.list("", "*")` |
| `get_unread_count` | `imap.status("INBOX", ["UNSEEN"])` |
| `modify_labels` | `uid_store` / `uid_copy` / `expunge` (flag vs. mailbox per RFC 3501) |
| `create_label` | `imap.create` |

It also provides:

- `initialize(host:, port:, username:, password:)` — opens `Net::IMAP` with SSL and logs in with password auth
- `on_exit` — logs out and disconnects
- `self.test_connection(**kwargs)` — calls `from_env(**kwargs).list_messages(max_results: 1)` with a class-name-derived success/failure message
- Private helpers: `imap`, `with_lock`, `ensure_mailbox`, `parse_mail`, `list_message`, `build_mailbox`, `imap_flag?`

The `provider` field in the message hash is derived from the class name at runtime:

```ruby
self.class.name.demodulize.delete_suffix("Adapter").downcase
# YahooAdapter → "yahoo"
# FastmailAdapter → "fastmail"
```

### 3. YahooAdapter after extraction

`YahooAdapter` owns exactly two methods:

```ruby
module Emails
  module Adapters
    class YahooAdapter < ImapAdapter
      def self.from_env(
        username: ENV["YAHOO_USERNAME"],
        password: ENV["YAHOO_APP_PASSWORD"],
        host:     ENV.fetch("YAHOO_IMAP_HOST", "imap.mail.yahoo.com"),
        port:     ENV.fetch("YAHOO_IMAP_PORT", "993").to_i
      )
        raise "Missing Yahoo credentials. Please set YAHOO_USERNAME and YAHOO_APP_PASSWORD." unless username && password
        new(host:, port:, username:, password:)
      end

      def self.setup(**_kwargs)
        puts "Yahoo setup: ..."
      end
    end
  end
end
```

Everything else — all seven interface methods, all helpers, connection lifecycle — is inherited from `ImapAdapter`.

### 4. Delete YahooMessageParser

`YahooMessageParser` is deleted. Its hash-building logic is inlined in `ImapAdapter#list_message`. The `provider` field is derived from the class name (see §2) rather than hardcoded.

### 5. Specs

Workflow coverage stays in `spec/lib/emails/adapters/yahoo_adapter_spec.rb`. All seven methods are tested through `YahooAdapter`, which exercises `ImapAdapter`'s implementation. No dedicated `ImapAdapter` spec.

`spec/lib/emails/adapters/yahoo_adapter_spec.rb` must be updated to remove all `instance_double(Net::IMAP)` usage. Use a real object, a lightweight fake class, or a test subclass instead.

### 6. RBS signatures

- Create `sig/lib/emails/adapters/imap_adapter.rbs`
- Delete `sig/lib/emails/adapters/yahoo_message_parser.rbs`
- Update `sig/lib/emails/adapters/yahoo_adapter.rbs` to reflect the slimmed class

## Technical Approach

### Files to change

| File | Change |
|------|--------|
| `lib/emails/adapters/imap_adapter.rb` | Create — all IMAP-generic logic from `YahooAdapter` |
| `lib/emails/adapters/yahoo_adapter.rb` | Slim to `from_env` + `self.setup` |
| `lib/emails/adapters/yahoo_message_parser.rb` | Delete |
| `sig/lib/emails/adapters/imap_adapter.rbs` | Create |
| `sig/lib/emails/adapters/yahoo_message_parser.rbs` | Delete |
| `sig/lib/emails/adapters/yahoo_adapter.rbs` | Update |
| `spec/lib/emails/adapters/yahoo_adapter_spec.rb` | Remove `instance_double` / `double` usage |

### Before and after

**Before (Yahoo owns everything):**

```ruby
class YahooAdapter < BaseAdapter
  # ~200 lines:
  # from_env, setup, test_connection
  # + search_messages, list_messages, get_message
  # + get_labels, get_unread_count, create_label, modify_labels
  # + with_lock, ensure_mailbox, parse_mail, imap, build_mailbox, imap_flag?
  # + on_exit
end
```

**After (IMAP mechanics live in ImapAdapter):**

```ruby
class ImapAdapter < BaseAdapter
  # ~180 lines: all of the above except from_env and setup
  # provider derived from self.class.name at runtime
end

class YahooAdapter < ImapAdapter
  def self.from_env(...) = new(...)   # reads YAHOO_* env vars
  def self.setup(...)   = puts "..."  # prints Yahoo instructions
end
```

## Success Criteria

- `ImapAdapter` implements all seven interface methods and all private IMAP helpers.
- `YahooAdapter` owns exactly `from_env` and `self.setup` — nothing else.
- `YahooMessageParser` is deleted; its RBS signature is deleted.
- Adding a third IMAP connector requires one new class file with `from_env` and `self.setup` — nothing else.
- `spec/lib/emails/adapters/yahoo_adapter_spec.rb` contains no `instance_double` or `double`.
- `steep check` passes.
