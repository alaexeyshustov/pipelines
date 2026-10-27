require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

class DbHelperTest < Minitest::Test
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

  def test_issue_to_branch_derives_the_branch_from_the_github_issue
    resolved = run_helper(
      "issue_to_branch",
      "#42",
      "STUB_GH_ISSUES" => issues("42" => { "title" => "Handle empty IMAP mailbox!", "labels" => ["bug"] })
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
      "STUB_GH_ISSUES" => issues("44" => { "title" => "Refactor pipelines", "labels" => ["refactor"] })
    )
    second = run_helper("issue_to_branch", "GH-44", "STUB_GH_FAILURE" => "true")

    assert_success first, "refactor/gh-44-refactor-pipelines\n"
    assert_success second, "refactor/gh-44-refactor-pipelines\n"
  end

  def test_issue_to_branch_accepts_an_issue_url
    resolved = run_helper(
      "issue_to_branch",
      "https://github.com/alaexeyshustov/pipelines/issues/45",
      "STUB_GH_ISSUES" => issues("45" => { "title" => "Docs", "labels" => ["documentation"] })
    )

    assert_success resolved, "chore/gh-45-docs\n"
  end

  def test_issue_to_branch_reports_a_missing_issue
    missing = run_helper("issue_to_branch", "46", "STUB_GH_ISSUES" => issues)

    refute missing.fetch(2).success?
    assert_includes missing.fetch(1), "Could not fetch GitHub issue #46"
  end

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

  def test_container_status_starts_created_and_can_be_updated
    worktree_path = File.join(@temporary_directory, "gh-124")
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", "GH-124", worktree_path, "--ticket=GH-124")
    run_helper("register_container", "GH-124", "claude-omcc")

    created = run_helper("get_container_status", "GH-124", "--profile=claude-omcc")
    updated = run_helper("update_container_status", "GH-124", "active", "--profile=claude-omcc")
    active = run_helper("get_container_status", "GH-124", "--profile=claude-omcc")

    assert_success created, "created\n"
    assert_success updated, ""
    assert_success active, "active\n"
  end

  def test_attach_marks_the_registered_container_active
    registered = run_helper(
      "register_worktree",
      "GH-125",
      File.expand_path("../..", __dir__),
      "--ticket=GH-125"
    )

    attached = run_attach("GH-125")
    status = run_helper("get_container_status", "GH-125", "--profile=claude-matt")

    assert_success registered, ""
    assert attached.fetch(2).success?, attached.fetch(1)
    assert_success status, "active\n"
  end

  def test_cleanup_finished_removes_the_container_worktree_and_mapping
    worktree_path = File.join(@temporary_directory, ".sandbox", "worktrees", "gh-126")
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", "GH-126", worktree_path, "--ticket=GH-126")
    run_helper("register_container", "GH-126", "claude-omcc")
    run_helper("update_container_status", "GH-126", "finished", "--profile=claude-omcc")

    cleaned = run_helper(
      "cleanup_finished",
      "STUB_GIT_WORKTREE_PATH" => File.realpath(worktree_path)
    )
    retrieved = run_helper("get_worktree", "GH-126")

    assert cleaned.fetch(2).success?, cleaned.fetch(1)
    assert_includes cleaned.fetch(0), "Cleaned up GH-126 (claude-omcc)."
    refute_path_exists worktree_path
    refute retrieved.fetch(2).success?
  end

  def test_cleanup_finished_marks_closed_github_issues_finished_before_cleaning
    worktree_path = File.join(@temporary_directory, ".sandbox", "worktrees", "gh-127")
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", "GH-127", worktree_path, "--ticket=GH-127")
    run_helper("register_container", "GH-127", "claude-omcc")
    run_helper("update_container_status", "GH-127", "active", "--profile=claude-omcc")

    cleaned = run_helper(
      "cleanup_finished",
      "STUB_GIT_WORKTREE_PATH" => File.realpath(worktree_path),
      "STUB_GH_ISSUES" => issues("127" => { "state" => "CLOSED" })
    )
    retrieved = run_helper("get_worktree", "GH-127")

    assert cleaned.fetch(2).success?, cleaned.fetch(1)
    assert_includes cleaned.fetch(0), "Marked GH-127 (claude-omcc) finished because its GitHub issue is closed."
    assert_includes cleaned.fetch(0), "Cleaned up GH-127 (claude-omcc)."
    refute_path_exists worktree_path
    refute retrieved.fetch(2).success?
  end

  def test_cleanup_finished_leaves_open_github_issues_active
    worktree_path = File.join(@temporary_directory, ".sandbox", "worktrees", "gh-131")
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", "GH-131", worktree_path, "--ticket=GH-131")
    run_helper("register_container", "GH-131", "claude-matt")
    run_helper("update_container_status", "GH-131", "active", "--profile=claude-matt")

    cleaned = run_helper("cleanup_finished", "STUB_GH_ISSUES" => issues("131" => { "state" => "OPEN" }))
    status = run_helper("get_container_status", "GH-131", "--profile=claude-matt")

    assert_success cleaned, "No finished sandbox containers.\n"
    assert_success status, "active\n"
    assert_path_exists worktree_path
  end

  def test_cleanup_finished_keeps_the_worktree_while_another_profile_is_still_active
    worktree_path = File.join(@temporary_directory, ".sandbox", "worktrees", "gh-128")
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", "GH-128", worktree_path, "--ticket=GH-128")
    run_helper("register_container", "GH-128", "claude-omcc")
    run_helper("register_container", "GH-128", "claude-matt")
    run_helper("update_container_status", "GH-128", "finished", "--profile=claude-omcc")

    cleaned = run_helper(
      "cleanup_finished",
      "STUB_GIT_WORKTREE_PATH" => File.realpath(worktree_path)
    )
    retrieved = run_helper("get_worktree", "GH-128")

    assert cleaned.fetch(2).success?, cleaned.fetch(1)
    assert_includes cleaned.fetch(0), "Cleaned up GH-128 (claude-omcc)."
    refute_includes cleaned.fetch(0), "Removed sandbox worktree for GH-128."
    assert_path_exists worktree_path
    assert retrieved.fetch(2).success?
  end

  def test_get_worktree_returns_the_latest_mapping
    first_path = File.join(@temporary_directory, "scratch-20260810123456-111")
    latest_path = File.join(@temporary_directory, "scratch-20260810123456-222")
    FileUtils.mkdir_p([first_path, latest_path])

    run_helper("register_worktree", "scratch-20260810123456-111", first_path)
    run_helper("register_worktree", "scratch-20260810123456-222", latest_path)

    retrieved = run_helper("get_worktree", "--latest")

    assert_success retrieved, "scratch-20260810123456-222\t#{File.realpath(latest_path)}\t\n"
  end

  def test_register_worktree_can_remove_a_worktree_mapping
    identifier = "scratch-20260810123456-333"
    worktree_path = File.join(@temporary_directory, identifier)
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", identifier, worktree_path)
    run_helper("register_container", identifier, "claude-omcc")

    removed = run_helper("register_worktree", "--remove=#{worktree_path}")
    retrieved = run_helper("get_worktree", identifier)
    status = run_helper("get_container_status", identifier, "--profile=claude-omcc")

    assert_success removed, ""
    refute retrieved.fetch(2).success?
    assert_includes retrieved.fetch(1), "No sandbox worktree is registered for #{identifier}."
    refute status.fetch(2).success?
  end

  def test_container_port_is_stable_per_container_and_unique_across_them
    worktree_path = File.join(@temporary_directory, "gh-129")
    FileUtils.mkdir_p(worktree_path)
    run_helper("register_worktree", "GH-129", worktree_path, "--ticket=GH-129")
    run_helper("register_container", "GH-129", "claude-omcc")
    run_helper("register_container", "GH-129", "claude-matt")

    first = run_helper("container_port", "GH-129", "--profile=claude-omcc")
    again = run_helper("container_port", "GH-129", "--profile=claude-omcc")
    other_profile = run_helper("container_port", "GH-129", "--profile=claude-matt")

    assert first.fetch(2).success?, first.fetch(1)
    assert_equal first.fetch(0), again.fetch(0), "the same container must keep its port"
    refute_equal first.fetch(0), other_profile.fetch(0), "concurrent containers must not share a port"
    [first, other_profile].each do |result|
      port = Integer(result.fetch(0).strip)
      assert_includes 3001..3099, port
    end
  end

  def test_container_port_requires_a_registered_container
    missing = run_helper("container_port", "GH-130", "--profile=claude-matt")

    refute missing.fetch(2).success?
    assert_includes missing.fetch(1), "No sandbox container is registered for GH-130 (claude-matt)."
  end

  def test_help_exposes_the_lifecycle_commands
    stdout, stderr, status = run_helper

    refute status.success?, stdout
    commands = stderr.lines.filter_map do |line|
      line[/^  db_helper (\w+)/, 1]
    end
    assert_equal %w[
      cleanup_finished
      container_port
      get_container_status
      get_worktree
      issue_to_branch
      register_container
      register_worktree
      update_container_status
    ], commands.sort
  end

  private

  def issues(definitions = {})
    JSON.generate(definitions)
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
    Open3.capture3(
      {
        "DB_HELPER_DATABASE_PATH" => @database_path,
        "HOME" => @home_directory,
        "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}"
      },
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
