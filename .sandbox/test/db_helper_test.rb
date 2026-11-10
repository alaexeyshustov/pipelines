require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

module DbHelperTestSupport
  DB_HELPER = File.expand_path("../bin/db_helper", __dir__)
  ATTACH_WORKTREE = File.expand_path("../bin/attach-worktree", __dir__)
  STUB_BIN = File.expand_path("support", __dir__)

  def setup
    @temporary_directory = Dir.mktmpdir("db-helper-test")
    @database_path = File.join(@temporary_directory, "sandbox.sqlite")
    @home_directory = File.join(@temporary_directory, "home")
    FileUtils.mkdir_p(File.join(@home_directory, ".claude-container"))
    File.write(File.join(@home_directory, ".claude-container", "oauth-token"), "token")
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory)
  end

  private

  def issues(definitions = {})
    JSON.generate(definitions)
  end

  # The checkout this test suite lives in, registered as a worktree by the attach tests.
  def worktree_root
    File.expand_path("../..", __dir__)
  end

  def sandbox_worktree_path(name)
    File.join(@temporary_directory, ".sandbox", "worktrees", name)
  end

  # Creates worktree_path and registers it for the GH-<number> identifier.
  def register_issue_worktree(identifier, worktree_path)
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", identifier, worktree_path, "--ticket=#{identifier}")
    worktree_path
  end

  def register_scratch_worktree(identifier)
    worktree_path = File.join(@temporary_directory, identifier)
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", identifier, worktree_path)
    worktree_path
  end

  def register_container(identifier, profile, status = nil)
    run_helper("register_container", identifier, profile)
    run_helper("update_container_status", identifier, status, "--profile=#{profile}") if status
  end

  def run_helper(*arguments)
    environment = arguments.last.is_a?(Hash) ? arguments.pop : {}
    Open3.capture3(
      {
        "DB_HELPER_DATABASE_PATH" => @database_path,
        "DB_HELPER_REPO_ROOT" => @temporary_directory,
        "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}"
      }.merge(environment),
      DB_HELPER,
      *arguments
    )
  end

  def run_attach(*arguments)
    environment = arguments.last.is_a?(Hash) ? arguments.pop : {}
    Open3.capture3(
      {
        "DB_HELPER_DATABASE_PATH" => @database_path,
        "HOME" => @home_directory,
        "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}"
      }.merge(environment),
      ATTACH_WORKTREE,
      *arguments
    )
  end

  def assert_success(result, expected_stdout)
    stdout, stderr, status = result
    assert status.success?, stderr
    assert_equal expected_stdout, stdout
  end
end

class DbHelperIssueToBranchTest < Minitest::Test
  include DbHelperTestSupport

  def test_issue_to_branch_derives_the_branch_from_the_github_issue
    resolved = run_helper(
      "issue_to_branch",
      "#42",
      "STUB_GH_ISSUES" => issues("42" => { "title" => "Handle empty IMAP mailbox!", "labels" => [ "bug" ] })
    )

    assert_success resolved, "fix/gh-42-handle-empty-imap-mailbox\n"
  end

  def test_issue_to_branch_uses_feat_for_unlabelled_issues_and_truncates_long_titles
    resolved = run_helper(
      "issue_to_branch",
      "43",
      "STUB_GH_ISSUES" => issues("43" => { "title" => "Add a very long feature description that keeps going well past the limit" })
    )

    assert_success resolved, "feat/gh-43-add-a-very-long-feature-description-that-keeps\n"
  end

  def test_issue_to_branch_ignores_urls_in_the_title
    resolved = run_helper(
      "issue_to_branch",
      "47",
      "STUB_GH_ISSUES" => issues("47" => { "title" => "Replace widgets.\nhttps://github.com/example/widgets" })
    )

    assert_success resolved, "feat/gh-47-replace-widgets\n"
  end

  def test_issue_to_branch_caches_the_branch_in_sqlite
    first = run_helper(
      "issue_to_branch",
      "gh-44",
      "STUB_GH_ISSUES" => issues("44" => { "title" => "Refactor pipelines", "labels" => [ "refactor" ] })
    )
    second = run_helper("issue_to_branch", "GH-44", "STUB_GH_FAILURE" => "true")

    assert_success first, "refactor/gh-44-refactor-pipelines\n"
    assert_success second, "refactor/gh-44-refactor-pipelines\n"
  end

  def test_issue_to_branch_accepts_an_issue_url
    resolved = run_helper(
      "issue_to_branch",
      "https://github.com/alaexeyshustov/pipelines/issues/45",
      "STUB_GH_ISSUES" => issues("45" => { "title" => "Docs", "labels" => [ "documentation" ] })
    )

    assert_success resolved, "chore/gh-45-docs\n"
  end

  def test_issue_to_branch_reports_a_missing_issue
    missing = run_helper("issue_to_branch", "46", "STUB_GH_ISSUES" => issues)

    refute missing.fetch(2).success?
    assert_includes missing.fetch(1), "Could not fetch GitHub issue #46"
  end

  def test_help_exposes_the_lifecycle_commands
    stdout, stderr, status = run_helper

    refute status.success?, stdout
    commands = stderr.lines.filter_map { |line| line[/^  db_helper (\w+)/, 1] }
    assert_equal %w[
      cleanup_finished container_port get_container_status get_worktree
      issue_to_branch register_container register_worktree update_container_status
    ], commands.sort
  end
end

class DbHelperWorktreeTest < Minitest::Test
  include DbHelperTestSupport

  def test_register_worktree_makes_an_issue_mapping_retrievable
    worktree_path = File.join(@temporary_directory, "gh-123")
    FileUtils.mkdir_p(worktree_path)

    registered = run_helper("register_worktree", "GH-123", worktree_path, "--ticket=GH-123")
    retrieved = run_helper("get_worktree", "GH-123")

    assert_success registered, ""
    assert_success retrieved, "GH-123\t#{File.realpath(worktree_path)}\tGH-123\n"
  end

  def test_get_worktree_finds_a_scratch_mapping_by_worktree
    identifier = "scratch-20260810123456-12345"
    worktree_path = File.join(@temporary_directory, identifier)
    FileUtils.mkdir_p(worktree_path)

    registered = run_helper("register_worktree", identifier, worktree_path)
    retrieved = run_helper("get_worktree", "--worktree=#{worktree_path}")

    assert_success registered, ""
    assert_success retrieved, "#{identifier}\t#{File.realpath(worktree_path)}\t\n"
  end

  def test_get_worktree_returns_the_latest_mapping
    register_scratch_worktree("scratch-20260810123456-111")
    latest_path = register_scratch_worktree("scratch-20260810123456-222")

    retrieved = run_helper("get_worktree", "--latest")

    assert_success retrieved, "scratch-20260810123456-222\t#{File.realpath(latest_path)}\t\n"
  end

  def test_register_worktree_can_remove_a_worktree_mapping
    identifier = "scratch-20260810123456-333"
    worktree_path = register_scratch_worktree(identifier)
    register_container(identifier, "claude-omcc")

    removed = run_helper("register_worktree", "--remove=#{worktree_path}")
    retrieved = run_helper("get_worktree", identifier)
    status = run_helper("get_container_status", identifier, "--profile=claude-omcc")

    assert_success removed, ""
    refute retrieved.fetch(2).success?
    assert_includes retrieved.fetch(1), "No sandbox worktree is registered for #{identifier}."
    refute status.fetch(2).success?
  end
end

class DbHelperContainerTest < Minitest::Test
  include DbHelperTestSupport

  def test_container_status_starts_created_and_can_be_updated
    register_issue_worktree("GH-124", File.join(@temporary_directory, "gh-124"))
    register_container("GH-124", "claude-omcc")

    created = run_helper("get_container_status", "GH-124", "--profile=claude-omcc")
    updated = run_helper("update_container_status", "GH-124", "active", "--profile=claude-omcc")
    active = run_helper("get_container_status", "GH-124", "--profile=claude-omcc")

    assert_success created, "created\n"
    assert_success updated, ""
    assert_success active, "active\n"
  end

  def test_container_port_is_stable_per_container_and_unique_across_them
    register_issue_worktree("GH-129", File.join(@temporary_directory, "gh-129"))
    register_container("GH-129", "claude-omcc")
    register_container("GH-129", "claude-matt")

    first = container_port("GH-129", "claude-omcc")
    again = container_port("GH-129", "claude-omcc")
    other_profile = container_port("GH-129", "claude-matt")

    assert_equal first, again, "the same container must keep its port"
    refute_equal first, other_profile, "concurrent containers must not share a port"
    assert_includes 3001..3099, first
    assert_includes 3001..3099, other_profile
  end

  def test_container_port_requires_a_registered_container
    missing = run_helper("container_port", "GH-130", "--profile=claude-matt")

    refute missing.fetch(2).success?
    assert_includes missing.fetch(1), "No sandbox container is registered for GH-130 (claude-matt)."
  end

  private

  def container_port(identifier, profile)
    stdout, stderr, status = run_helper("container_port", identifier, "--profile=#{profile}")
    assert status.success?, stderr
    Integer(stdout.strip)
  end
end

class DbHelperAttachTest < Minitest::Test
  include DbHelperTestSupport

  def test_attach_marks_the_registered_container_active
    registered = run_helper("register_worktree", "GH-125", worktree_root, "--ticket=GH-125")

    attached = run_attach("GH-125")
    status = run_helper("get_container_status", "GH-125", "--profile=claude-matt")

    assert_success registered, ""
    assert attached.fetch(2).success?, attached.fetch(1)
    assert_success status, "active\n"
  end

  # sqlite-vec publishes no gem Linux Ruby on arm64 can select, so sandboxes
  # run as amd64 (Rosetta on Apple Silicon) with per-arch images and volumes.
  def test_attach_builds_and_runs_the_sandbox_as_amd64
    attached, calls = attach_logging_podman("GH-132", "STUB_PODMAN_IMAGE_MISSING" => "true")
    build = calls.find { _1.start_with?("build ") }

    assert attached.fetch(2).success?, attached.fetch(1)
    assert_includes build, "--platform linux/amd64"
    assert_match %r{--tag pipelines-claude-matt-agent-amd64:\h{64}}, build
    assert_amd64_run(calls.find { _1.start_with?("run ") })
  end

  # A linked worktree's gitdir points back at the worktree's host path; mounted
  # anywhere else, git and Claude Code's worktree isolation treat it as stale.
  def test_attach_mounts_the_worktree_at_its_host_path
    worktree_path = File.realpath(worktree_root)
    attached, calls = attach_logging_podman("GH-133")
    run = calls.find { _1.start_with?("run ") }

    assert attached.fetch(2).success?, attached.fetch(1)
    assert_includes run, "--workdir #{worktree_path}"
    assert_includes run, "type=bind,src=#{worktree_path},dst=#{worktree_path}"
    assert_includes run, "SANDBOX_WORKSPACE=#{worktree_path}"
    refute_includes run, "/workspace"
  end

  # A cgroup cap keeps an overrun (e.g. steep workers) inside one sandbox
  # instead of triggering a VM-wide OOM that kills other sessions' agents.
  def test_attach_caps_the_container_memory
    run_helper("register_worktree", "GH-132", worktree_root, "--ticket=GH-132")
    log = File.join(@temporary_directory, "podman.log")

    run_attach("GH-132", "STUB_PODMAN_LOG" => log)
    run_attach("GH-132", "STUB_PODMAN_LOG" => log, "SANDBOX_MEMORY" => "5g")
    default_run, overridden_run = File.readlines(log, chomp: true).select { _1.start_with?("run ") }

    assert_includes default_run, "--memory 3g"
    assert_includes overridden_run, "--memory 5g"
  end

  private

  # Registers the worktree, attaches it with the podman stub logging its
  # calls, and returns the attach result with the logged podman calls.
  def attach_logging_podman(identifier, environment = {})
    run_helper("register_worktree", identifier, worktree_root, "--ticket=#{identifier}")
    log = File.join(@temporary_directory, "podman.log")
    attached = run_attach(identifier, { "STUB_PODMAN_LOG" => log }.merge(environment))
    [ attached, File.readlines(log, chomp: true) ]
  end

  def assert_amd64_run(run)
    assert_includes run, "--platform linux/amd64"
    assert_match %r{src=pipelines-claude-matt-[a-z0-9-]+-bundle-amd64,dst=/bundle}, run
    assert_match %r{src=pipelines-claude-matt-[a-z0-9-]+-node-modules-amd64,dst=#{Regexp.escape(File.realpath(worktree_root))}/node_modules}, run
  end
end

class DbHelperCleanupFinishedTest < Minitest::Test
  include DbHelperTestSupport

  def test_cleanup_finished_removes_the_container_worktree_and_mapping
    worktree_path = register_issue_worktree("GH-126", sandbox_worktree_path("gh-126"))
    register_container("GH-126", "claude-omcc", "finished")

    cleaned = cleanup_finished(worktree_path)

    assert_includes cleaned, "Cleaned up GH-126 (claude-omcc)."
    refute_path_exists worktree_path
    refute worktree_registered?("GH-126")
  end

  def test_cleanup_finished_marks_closed_github_issues_finished_before_cleaning
    worktree_path = register_issue_worktree("GH-127", sandbox_worktree_path("gh-127"))
    register_container("GH-127", "claude-omcc", "active")

    cleaned = cleanup_finished(worktree_path, "STUB_GH_ISSUES" => issues("127" => { "state" => "CLOSED" }))

    assert_includes cleaned, "Marked GH-127 (claude-omcc) finished because its GitHub issue is closed."
    assert_includes cleaned, "Cleaned up GH-127 (claude-omcc)."
    refute_path_exists worktree_path
    refute worktree_registered?("GH-127")
  end

  def test_cleanup_finished_leaves_open_github_issues_active
    worktree_path = register_issue_worktree("GH-131", sandbox_worktree_path("gh-131"))
    register_container("GH-131", "claude-matt", "active")

    cleaned = run_helper("cleanup_finished", "STUB_GH_ISSUES" => issues("131" => { "state" => "OPEN" }))
    status = run_helper("get_container_status", "GH-131", "--profile=claude-matt")

    assert_success cleaned, "No finished sandbox containers.\n"
    assert_success status, "active\n"
    assert_path_exists worktree_path
  end

  def test_cleanup_finished_keeps_the_worktree_while_another_profile_is_still_active
    worktree_path = register_issue_worktree("GH-128", sandbox_worktree_path("gh-128"))
    register_container("GH-128", "claude-omcc", "finished")
    register_container("GH-128", "claude-matt")

    cleaned = cleanup_finished(worktree_path)

    assert_includes cleaned, "Cleaned up GH-128 (claude-omcc)."
    refute_includes cleaned, "Removed sandbox worktree for GH-128."
    assert_path_exists worktree_path
    assert worktree_registered?("GH-128")
  end

  private

  # Runs cleanup_finished with the git stub owning worktree_path and returns
  # its output once it has succeeded.
  def cleanup_finished(worktree_path, environment = {})
    stdout, stderr, status = run_helper(
      "cleanup_finished",
      { "STUB_GIT_WORKTREE_PATH" => File.realpath(worktree_path) }.merge(environment)
    )
    assert status.success?, stderr
    stdout
  end

  def worktree_registered?(identifier)
    run_helper("get_worktree", identifier).fetch(2).success?
  end
end
