#!/usr/bin/env ruby

begin
  gem 'dry-cli', '~> 1.1'
  gem 'sqlite3', '>= 2.1'
rescue Gem::MissingSpecError => e
  abort "Error: #{e.message}. Run: gem install dry-cli sqlite3"
end

require 'dry/cli'
require 'json'
require 'open3'
require 'socket'
require 'sqlite3'

module DbHelper
  BRANCH_PATTERN = %r{\A(?:feat|fix|refactor|chore)/gh-\d+(?:-[a-z0-9]+)*\z}
  IDENTIFIER_PATTERN = /\A(?:GH-\d+|scratch-\d{14}-\d+)\z/
  PROFILE_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  CONTAINER_STATUSES = %w[created active finished].freeze

  # Branch type prefix by GitHub label; the first matching label wins and an
  # issue with none of them is a feature.
  LABEL_BRANCH_TYPES = {
    'bug' => 'fix',
    'refactor' => 'refactor',
    'documentation' => 'chore',
    'chore' => 'chore'
  }.freeze
  BRANCH_SLUG_LENGTH = 50

  # Host ports handed out for forwarding to each sandbox's port 3000. Starts
  # above 3000 because that is where a host-side dev server usually already
  # listens, and a container cannot be reached on a port the host has taken.
  SANDBOX_PORT_RANGE = (3001..3099).freeze

  class Error < StandardError; end

  module Database
    module_function

    def open
      database_path = ENV.fetch(
        'DB_HELPER_DATABASE_PATH',
        File.join(File.dirname(File.realpath(__FILE__)), 'sandbox.sqlite')
      )

      database = SQLite3::Database.new(database_path)
      database.busy_timeout = 5_000
      database.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS issues (
          number INTEGER PRIMARY KEY,
          title TEXT NOT NULL,
          state TEXT NOT NULL,
          branch TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS worktrees (
          identifier TEXT PRIMARY KEY,
          worktree_path TEXT NOT NULL,
          ticket TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS index_worktrees_on_worktree_path
          ON worktrees(worktree_path);

        CREATE TABLE IF NOT EXISTS sandbox_containers (
          identifier TEXT NOT NULL,
          profile TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'created' CHECK(status IN ('created', 'active', 'finished')),
          host_port INTEGER,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (identifier, profile)
        );

        CREATE INDEX IF NOT EXISTS index_sandbox_containers_on_identifier
          ON sandbox_containers(identifier);

        CREATE UNIQUE INDEX IF NOT EXISTS index_sandbox_containers_on_host_port
          ON sandbox_containers(host_port) WHERE host_port IS NOT NULL;
      SQL
      database
    end
  end

  module Container
    module_function

    def validate_identifier(identifier)
      return identifier if identifier.match?(IDENTIFIER_PATTERN)

      raise Error, "Invalid sandbox identifier: #{identifier}"
    end

    def validate_profile(profile)
      return profile if profile.match?(PROFILE_PATTERN)

      raise Error, "Invalid sandbox profile: #{profile}"
    end

    def validate_status(status)
      return status if CONTAINER_STATUSES.include?(status)

      raise Error, "Status must be one of: #{CONTAINER_STATUSES.join(', ')}."
    end
  end

  module Worktree
    module_function

    def primary_repo_root
      root = ENV.fetch(
        'DB_HELPER_REPO_ROOT',
        File.expand_path('../..', File.dirname(File.realpath(__FILE__)))
      )
      File.realpath(root)
    end

    def registered?(worktree_path)
      output, status = Open3.capture2(
        'git', 'worktree', 'list', '--porcelain',
        chdir: primary_repo_root
      )
      raise Error, 'Could not list Git worktrees.' unless status.success?

      output.each_line.any? do |line|
        path = line.delete_prefix('worktree ').chomp
        line.start_with?('worktree ') && File.expand_path(path) == File.expand_path(worktree_path)
      end
    end

    def remove(worktree_path)
      success = system(
        'git', 'worktree', 'remove', '--force', worktree_path,
        chdir: primary_repo_root
      )
      raise Error, "Could not remove Git worktree: #{worktree_path}" unless success
    end

    def prune
      success = system('git', 'worktree', 'prune', chdir: primary_repo_root)
      raise Error, 'Could not prune Git worktrees.' unless success
    end
  end

  module Issue
    module_function

    # Accepts 42, #42, gh-42, GH-42, or an issue URL; returns GH-42.
    def normalize(issue)
      number = issue[/\A(?:#|gh-)?(\d+)\z/i, 1] || issue[%r{\Ahttps://github\.com/[^/]+/[^/]+/issues/(\d+)(?:[/?#].*)?\z}, 1]
      raise Error, 'Issue must be a GitHub issue number (42, #42, GH-42) or an issue URL.' unless number

      "GH-#{number}"
    end

    def number(identifier)
      Integer(identifier.delete_prefix('GH-'))
    end

    def fetch(number)
      output, error, status = Open3.capture3(
        'gh', 'issue', 'view', number.to_s, '--json', 'number,title,state,labels',
        chdir: Worktree.primary_repo_root
      )
      raise Error, "Could not fetch GitHub issue ##{number}: #{error.strip}" unless status.success?

      JSON.parse(output)
    end

    def branch_for(issue)
      labels = issue.fetch('labels').map { |label| label.fetch('name').downcase }
      type = LABEL_BRANCH_TYPES.find { |label, _type| labels.include?(label) }&.last || 'feat'
      slug = slugify(issue.fetch('title'))

      [ "#{type}/gh-#{issue.fetch('number')}", slug ].reject(&:empty?).join('-')
    end

    def slugify(title)
      slug = title.gsub(%r{https?://\S+}, ' ')
                  .unicode_normalize(:nfkd)
                  .encode('ASCII', invalid: :replace, undef: :replace, replace: '')
                  .downcase
                  .gsub(/[^a-z0-9]+/, '-')
                  .delete_prefix('-')
                  .delete_suffix('-')
      return slug if slug.length <= BRANCH_SLUG_LENGTH

      truncated = slug[0, BRANCH_SLUG_LENGTH + 1]
      truncated[0, truncated.rindex('-') || BRANCH_SLUG_LENGTH].delete_suffix('-')
    end
  end

  module Commands
    extend Dry::CLI::Registry

    class IssueToBranch < Dry::CLI::Command
      desc 'Resolve and cache a branch name for a GitHub issue'

      argument :issue, required: true, desc: 'Issue number, GH-<number>, or issue URL'

      def call(issue:, **)
        number = Issue.number(Issue.normalize(issue))
        database = Database.open
        cached_branch = database.get_first_value('SELECT branch FROM issues WHERE number = ? LIMIT 1;', [number])

        if cached_branch&.match?(BRANCH_PATTERN)
          puts cached_branch
          return
        end

        details = Issue.fetch(number)
        branch = Issue.branch_for(details)
        raise Error, "Derived an invalid branch name: #{branch}" unless branch.match?(BRANCH_PATTERN)

        database.execute(
          <<~SQL,
            INSERT INTO issues (number, title, state, branch)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(number) DO UPDATE SET
              title = excluded.title,
              state = excluded.state,
              branch = excluded.branch,
              updated_at = CURRENT_TIMESTAMP;
          SQL
          [number, details.fetch('title'), details.fetch('state'), branch]
        )
        puts branch
      ensure
        database&.close
      end
    end

    class RegisterWorktree < Dry::CLI::Command
      desc 'Register a sandbox worktree for an issue or scratch name, independent of any profile'

      argument :identifier, required: false, desc: 'GH-<number> or generated scratch name'
      argument :worktree_path, required: false, desc: 'Git worktree path'
      option :ticket, type: :string, desc: 'GitHub issue identifier (GH-<number>)'
      option :remove, type: :string, desc: 'Remove the worktree mapping (and its sandbox containers) for a worktree path'

      def call(identifier: nil, worktree_path: nil, ticket: nil, remove: nil, **)
        if remove
          if identifier || worktree_path || ticket
            raise Error, '--remove cannot be combined with registration arguments.'
          end

          remove_worktree_mapping(remove)
          return
        end

        unless identifier && worktree_path
          raise Error, 'Registration requires an identifier and a worktree path.'
        end

        identifier = Container.validate_identifier(identifier)
        worktree_path = File.realpath(worktree_path)
        if ticket && ticket != identifier
          raise Error, 'Ticket must match the registry identifier.'
        end

        database = Database.open
        database.execute(
          <<~SQL,
            INSERT INTO worktrees (identifier, worktree_path, ticket)
            VALUES (?, ?, ?)
            ON CONFLICT(identifier) DO UPDATE SET
              worktree_path = excluded.worktree_path,
              ticket = excluded.ticket,
              updated_at = CURRENT_TIMESTAMP;
          SQL
          [identifier, worktree_path, ticket]
        )
      ensure
        database&.close
      end

      private

      def remove_worktree_mapping(worktree_path)
        worktree_path = if File.exist?(worktree_path)
                          File.realpath(worktree_path)
                        else
                          File.expand_path(worktree_path)
                        end
        database = Database.open
        identifiers = database.execute('SELECT identifier FROM worktrees WHERE worktree_path = ?;', [worktree_path]).flatten
        identifiers.each do |identifier|
          database.execute('DELETE FROM sandbox_containers WHERE identifier = ?;', [identifier])
        end
        database.execute('DELETE FROM worktrees WHERE worktree_path = ?;', [worktree_path])
      ensure
        database&.close
      end
    end

    class GetWorktree < Dry::CLI::Command
      desc 'Get a registered sandbox worktree'

      argument :identifier, required: false, desc: 'GH-<number> or generated scratch name'
      option :worktree, type: :string, desc: 'Find the worktree by its path'
      option :latest, type: :boolean, default: false, desc: 'Get the most recently registered worktree'

      def call(identifier: nil, worktree: nil, latest: false, **)
        lookup_count = [identifier, worktree, latest].count { |lookup| lookup }
        if lookup_count != 1
          raise Error, 'Provide exactly one of an identifier, --worktree, or --latest.'
        end

        database = Database.open
        if identifier
          identifier = Container.validate_identifier(identifier)
          record = database.get_first_row(
            "SELECT identifier, worktree_path, COALESCE(ticket, '') FROM worktrees WHERE identifier = ? LIMIT 1;",
            [identifier]
          )
          missing_mapping = identifier
        elsif worktree
          worktree = File.realpath(worktree)
          record = database.get_first_row(
            "SELECT identifier, worktree_path, COALESCE(ticket, '') FROM worktrees WHERE worktree_path = ? LIMIT 1;",
            [worktree]
          )
          missing_mapping = worktree
        else
          record = database.get_first_row(
            "SELECT identifier, worktree_path, COALESCE(ticket, '') FROM worktrees " \
              'ORDER BY updated_at DESC, rowid DESC LIMIT 1;'
          )
          missing_mapping = 'the latest worktree'
        end
        unless record
          raise Error, "No sandbox worktree is registered for #{missing_mapping}. Run init-worktree first."
        end

        puts record.join("\t")
      ensure
        database&.close
      end
    end

    class RegisterContainer < Dry::CLI::Command
      desc 'Register (or touch) the sandbox container lifecycle row for a worktree profile'

      argument :identifier, required: true, desc: 'GH-<number> or generated scratch name'
      argument :profile, required: true, desc: 'Sandbox profile name'

      def call(identifier:, profile:, **)
        identifier = Container.validate_identifier(identifier)
        profile = Container.validate_profile(profile)

        database = Database.open
        unless database.get_first_value('SELECT 1 FROM worktrees WHERE identifier = ? LIMIT 1;', [identifier])
          raise Error, "No sandbox worktree is registered for #{identifier}. Run init-worktree first."
        end

        database.execute(
          <<~SQL,
            INSERT INTO sandbox_containers (identifier, profile)
            VALUES (?, ?)
            ON CONFLICT(identifier, profile) DO UPDATE SET updated_at = CURRENT_TIMESTAMP;
          SQL
          [identifier, profile]
        )
      ensure
        database&.close
      end
    end

    class GetContainerStatus < Dry::CLI::Command
      desc 'Get the current lifecycle status for a sandbox container'

      argument :identifier, required: true, desc: 'GH-<number> or generated scratch name'
      option :profile, required: true, type: :string, desc: 'Sandbox profile name'

      def call(identifier:, profile:, **)
        identifier = Container.validate_identifier(identifier)
        profile = Container.validate_profile(profile)
        database = Database.open
        status = database.get_first_value(
          'SELECT status FROM sandbox_containers WHERE identifier = ? AND profile = ? LIMIT 1;',
          [identifier, profile]
        )
        unless status
          raise Error, "No sandbox container is registered for #{identifier} (#{profile}). Run init-worktree first."
        end

        puts status
      ensure
        database&.close
      end
    end

    class UpdateContainerStatus < Dry::CLI::Command
      desc 'Update the lifecycle status for a sandbox container'

      argument :identifier, required: true, desc: 'GH-<number> or generated scratch name'
      argument :status, required: true, desc: 'created, active, or finished'
      option :profile, required: true, type: :string, desc: 'Sandbox profile name'

      def call(identifier:, status:, profile:, **)
        identifier = Container.validate_identifier(identifier)
        status = Container.validate_status(status)
        profile = Container.validate_profile(profile)
        database = Database.open
        database.execute(
          'UPDATE sandbox_containers SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE identifier = ? AND profile = ?;',
          [status, identifier, profile]
        )
        if database.changes.zero?
          raise Error, "No sandbox container is registered for #{identifier} (#{profile}). Run init-worktree first."
        end
      ensure
        database&.close
      end
    end

    class ContainerPort < Dry::CLI::Command
      desc 'Get the host port forwarded to a sandbox container, allocating one on first use'

      argument :identifier, required: true, desc: 'GH-<number> or generated scratch name'
      option :profile, required: true, type: :string, desc: 'Sandbox profile name'

      def call(identifier:, profile:, **)
        identifier = Container.validate_identifier(identifier)
        profile = Container.validate_profile(profile)
        database = Database.open

        record = database.get_first_row(
          'SELECT host_port FROM sandbox_containers WHERE identifier = ? AND profile = ? LIMIT 1;',
          [identifier, profile]
        )
        unless record
          raise Error, "No sandbox container is registered for #{identifier} (#{profile}). Run init-worktree first."
        end

        host_port = record.first
        if host_port.nil?
          host_port = allocate_port(database)
          database.execute(
            'UPDATE sandbox_containers SET host_port = ?, updated_at = CURRENT_TIMESTAMP ' \
              'WHERE identifier = ? AND profile = ?;',
            [host_port, identifier, profile]
          )
        end

        puts host_port
      ensure
        database&.close
      end

      private

      # The allocation is stored, so a container keeps the same port across
      # restarts and the URL stays stable.
      def allocate_port(database)
        reserved = database.execute(
          'SELECT host_port FROM sandbox_containers WHERE host_port IS NOT NULL;'
        ).flatten

        candidate = SANDBOX_PORT_RANGE.find do |port|
          !reserved.include?(port) && bindable?(port)
        end
        unless candidate
          raise Error, 'No free host port between ' \
            "#{SANDBOX_PORT_RANGE.first} and #{SANDBOX_PORT_RANGE.last} for sandbox forwarding."
        end

        candidate
      end

      # A port held by something outside this registry -- a host dev server,
      # an unrelated tool -- would make `podman run --publish` fail at launch,
      # so skip it here instead of storing a port that cannot bind.
      def bindable?(port)
        server = TCPServer.new('127.0.0.1', port)
        true
      rescue Errno::EADDRINUSE, Errno::EACCES
        false
      ensure
        server&.close
      end
    end

    class CleanupFinished < Dry::CLI::Command
      desc 'Remove containers and worktrees whose lifecycle status is finished'

      def call(**)
        database = Database.open
        mark_closed_issues_finished(database)
        records = database.execute(
          <<~SQL
            SELECT sandbox_containers.identifier, sandbox_containers.profile, worktrees.worktree_path
            FROM sandbox_containers
            JOIN worktrees ON worktrees.identifier = sandbox_containers.identifier
            WHERE sandbox_containers.status = 'finished'
            ORDER BY sandbox_containers.updated_at, sandbox_containers.rowid;
          SQL
        )

        if records.empty?
          puts 'No finished sandbox containers.'
          return
        end

        touched_identifiers = []
        records.each do |identifier, profile, worktree_path|
          container_name = container_name_for(profile, worktree_path)
          cleanup_container(container_name)
          database.execute(
            'DELETE FROM sandbox_containers WHERE identifier = ? AND profile = ?;',
            [identifier, profile]
          )
          touched_identifiers << identifier
          puts "Cleaned up #{identifier} (#{profile})."
        end

        touched_identifiers.uniq.each do |identifier|
          remaining = database.get_first_value(
            'SELECT COUNT(*) FROM sandbox_containers WHERE identifier = ?;',
            [identifier]
          )
          next unless remaining.zero?

          worktree_path = database.get_first_value(
            'SELECT worktree_path FROM worktrees WHERE identifier = ?;',
            [identifier]
          )
          cleanup_worktree(worktree_path) if worktree_path
          database.execute('DELETE FROM worktrees WHERE identifier = ?;', [identifier])
          puts "Removed sandbox worktree for #{identifier}. Its Git branch was retained."
        end
        Worktree.prune
      ensure
        database&.close
      end

      private

      def container_name_for(profile, worktree_path)
        "pipelines-#{profile}-#{File.basename(worktree_path)}"
      end

      # Refreshes the cached issue state from GitHub and finishes every active
      # container whose issue has been closed.
      def mark_closed_issues_finished(database)
        active_tickets = database.execute(
          <<~SQL
            SELECT sandbox_containers.identifier, sandbox_containers.profile, worktrees.ticket
            FROM sandbox_containers
            JOIN worktrees ON worktrees.identifier = sandbox_containers.identifier
            WHERE sandbox_containers.status = 'active' AND worktrees.ticket IS NOT NULL
            ORDER BY sandbox_containers.updated_at, sandbox_containers.rowid;
          SQL
        )
        return if active_tickets.empty?

        closed_tickets = active_tickets.map { |_identifier, _profile, ticket| ticket }.uniq.select do |ticket|
          refresh_issue_state(database, ticket) == 'CLOSED'
        end

        active_tickets.each do |identifier, profile, ticket|
          next unless closed_tickets.include?(ticket)

          database.execute(
            "UPDATE sandbox_containers SET status = 'finished', updated_at = CURRENT_TIMESTAMP " \
              'WHERE identifier = ? AND profile = ?;',
            [identifier, profile]
          )
          puts "Marked #{identifier} (#{profile}) finished because its GitHub issue is closed."
        end
      end

      def refresh_issue_state(database, ticket)
        number = Issue.number(ticket)
        state = Issue.fetch(number).fetch('state')
        database.execute(
          'UPDATE issues SET state = ?, updated_at = CURRENT_TIMESTAMP WHERE number = ?;',
          [state, number]
        )
        state
      end

      def cleanup_container(container_name)
        return unless system('podman', 'container', 'exists', container_name)

        puts "Removing sandbox container: #{container_name}"
        success = system('podman', 'container', 'rm', '--force', container_name)
        raise Error, "Could not remove sandbox container: #{container_name}" unless success
      end

      def cleanup_worktree(worktree_path)
        unless worktree_path.start_with?("#{File.expand_path(Worktree.primary_repo_root)}/.sandbox/worktrees/")
          raise Error, "Registered worktree is outside .sandbox/worktrees: #{worktree_path}"
        end

        if Worktree.registered?(worktree_path)
          puts "Removing Git worktree: #{worktree_path}"
          Worktree.remove(worktree_path)
        elsif File.exist?(worktree_path)
          raise Error, "Worktree path is not registered by Git: #{worktree_path}"
        end
      end
    end

    register 'issue_to_branch', IssueToBranch
    register 'register_worktree', RegisterWorktree
    register 'get_worktree', GetWorktree
    register 'register_container', RegisterContainer
    register 'get_container_status', GetContainerStatus
    register 'update_container_status', UpdateContainerStatus
    register 'container_port', ContainerPort
    register 'cleanup_finished', CleanupFinished
  end
end

begin
  Dry::CLI.new(DbHelper::Commands).call
rescue DbHelper::Error, JSON::ParserError, KeyError => e
  warn "Error: #{e.message}"
  exit 1
end
