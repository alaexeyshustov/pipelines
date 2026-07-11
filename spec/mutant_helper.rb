require 'rails_helper'

Rails.application.eager_load!

# Mutant forks `--jobs N` persistent worker processes that all inherit this
# process's already-open primary connection to storage/test.sqlite3. Every
# worker then hammers that single on-disk file concurrently, producing
# SQLite3::BusyException ("database is locked") and false mutant "Neutral
# failure" results that contaminate the measured mutation score (see
# docs/claude/gotchas.md and RALPLAN-DR v2.1's Step 1 measurement spike:
# --jobs 2 did not reliably eliminate contention across 3 reruns, and
# --jobs 1 does not fit the 6h CI ceiling, so tolerance-only fixes alone
# were insufficient).
#
# Give every forked worker its own private copy of the primary DB instead.
#
# Mutant ALSO forks a second, nested time per individual mutation kill
# attempt (Mutant::Isolation::Fork, aka "killfork") *inside* each persistent
# worker, to isolate a single test run from the worker loop. ForkTracker
# fires on every fork, including these nested ones -- so this hook is
# guarded by MUTANT_ISOLATED_TEST_DB (inherited via ENV across nested
# forks) to run its file-copy + establish_connection dance exactly once,
# at the top-level worker fork. Without this guard, every single mutation
# re-copies the DB and re-establishes a connection mid-flight, which
# corrupts mutant's marshaled IPC between a killfork child and its parent
# (observed as `ArgumentError: marshal data too short`) and collapses the
# measured coverage toward zero.
#
# `establish_connection` with a bare (unnamed) config hash swaps the *live*
# connection but leaves `ActiveRecord::Base.configurations`'s "primary"
# entry pointing at the original shared file. Replacing the registry entry
# itself (not just the live connection) means any later by-name reconnect
# also resolves to the worker's own private copy.
#
# This file is loaded ONLY via `.mutant.yml`'s `requires: mutant_helper`; a
# plain `bundle exec rspec` run never requires it, so this hook can never
# register (or fire) outside a mutant run.
if ActiveRecord::Base.connected?
  # Flush any pending WAL frames into the main file before any worker copies
  # it, so every worker's copy is a complete, self-contained snapshot (the
  # test DB uses journal_mode: wal, see config/database.yml).
  ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')
end

ActiveSupport::ForkTracker.after_fork do
  next if ENV['MUTANT_ISOLATED_TEST_DB']

  primary_config = ActiveRecord::Base.connection_db_config
  template_path  = Rails.root.join(primary_config.database)
  worker_path    = Rails.root.join("storage/test.#{Process.pid}.sqlite3")

  FileUtils.cp(template_path, worker_path)

  new_hash = primary_config.configuration_hash.merge(database: worker_path.to_s)

  # Replace the "primary" entry in the named configuration registry (not
  # just the live connection) so any later by-name reconnect resolves to
  # this worker's private copy instead of the shared template file.
  replacement_configs = ActiveRecord::Base.configurations.configurations.map do |config|
    if config.env_name == primary_config.env_name && config.name == primary_config.name
      ActiveRecord::DatabaseConfigurations::HashConfig.new(config.env_name, config.name, new_hash)
    else
      config
    end
  end
  ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(replacement_configs)

  # Rails' own fork handling may already have cleared the inherited pool;
  # do it explicitly too so we never establish a second connection on top
  # of a stale inherited file descriptor.
  ActiveRecord::Base.connection_handler.clear_all_connections!
  ActiveRecord::Base.establish_connection(primary_config.name.to_sym)

  # Inherited by any nested killfork children so the guard above skips them.
  ENV['MUTANT_ISOLATED_TEST_DB'] = worker_path.to_s

  # Mutant's nested per-mutation "killfork" (Mutant::Isolation::Fork) is a
  # plain block-form Process.fork, which runs a normal Ruby VM shutdown --
  # including any at_exit procs already registered in this process -- once
  # the killfork's block returns. Without the owner_pid guard, every single
  # killfork (there is one per mutation, all still running inside this same
  # worker) re-fires this at_exit and deletes the worker's own private DB
  # file out from under itself while the worker is still alive and processing
  # further mutations, producing `Could not find table` errors intermittently.
  owner_pid = Process.pid
  at_exit do
    next unless Process.pid == owner_pid

    FileUtils.rm_f(worker_path)
    FileUtils.rm_f("#{worker_path}-wal")
    FileUtils.rm_f("#{worker_path}-shm")
  end
end

# RESOLVED (2026-07-11): the ~3.2% (11/343) intermittent
# `ActiveRecord::StatementInvalid: Could not find table` failures previously
# seen here were caused by the `at_exit` hook above firing inside mutant's
# nested per-mutation "killfork" (Mutant::Isolation::Fork), not just at
# true worker shutdown. Mutant's killfork is a plain block-form
# `Process.fork { ... }`, forked from *inside* this persistent worker after
# this hook already ran and registered the at_exit; a killfork child
# inherits that registration, and Ruby runs normal at_exit processing when
# the killfork's block returns (confirmed with a minimal standalone
# Process.fork repro, independent of Rails/mutant). So every single
# mutation's killfork was deleting the worker's own private DB file out
# from under the still-running worker, not just the worker's real exit --
# explaining why it reproduced identically at --jobs 1 (not a cross-worker
# race) and why it was timing-sensitive (which killfork "won" the race
# against the parent's next query varied run to run). Fixed by guarding the
# at_exit body with an `owner_pid` check so only the process that actually
# registered it performs the deletion; nested killforks now no-op. Verified
# with 0 occurrences of `Could not find table` across 2 reruns each at
# --jobs 1 and --jobs 2 on the same representative 343-mutation slice.
