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

  at_exit do
    FileUtils.rm_f(worker_path)
    FileUtils.rm_f("#{worker_path}-wal")
    FileUtils.rm_f("#{worker_path}-shm")
  end
end

# KNOWN LIMITATION (2026-07-11, tracked follow-up -- do not silently
# "fix" by tuning thresholds around it): on a representative 343-mutation
# scoped run, this isolation eliminates SQLite3::BusyException entirely
# (0 occurrences across 6+ reruns at --jobs 1 and --jobs 2), but a small,
# fully deterministic subset (11/343, ~3.2%, always mutant's "neutral"-type
# self-verification mutations -- semantically inert transformations mutant
# generates as an internal sanity check, not real coverage) shows
# `ActiveRecord::StatementInvalid: Could not find table`. Root cause was
# narrowed to the worker's private DB file intermittently reading back as
# `File.exist? == true` but `File.size == 0` inside a killfork, but NOT
# fully resolved despite trying: replacing the named configuration registry
# entry (necessary, kept above, but insufficient alone), forcing
# journal_mode away from WAL, forcing a fresh reconnect at the start of
# every example (made things categorically worse -- broke transactional
# fixtures), and explicit connection.disconnect! before reconnecting (also
# made things worse). Reproduces identically at --jobs 1, ruling out
# cross-worker concurrency. Follow-up needed before the measured mutation
# score can be treated as fully clean; see the Ralph run's final report for
# the day this was found.
