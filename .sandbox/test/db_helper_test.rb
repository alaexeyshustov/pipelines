require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "sandbox_fixtures"

module DbHelperTestSupport
  DB_HELPER = File.expand_path("../bin/db_helper", __dir__)
  ATTACH_WORKTREE = File.expand_path("../bin/attach-worktree", __dir__)
  RECREATE_WORKTREE = File.expand_path("../bin/recreate-worktree", __dir__)
  SANDBOX_NETWORK = File.expand_path("../bin/sandbox-network", __dir__)
  STUB_BIN = File.expand_path("support", __dir__)

  def setup
    @temporary_directory = Dir.mktmpdir("db-helper-test")
    @database_path = File.join(@temporary_directory, "sandbox.sqlite")
    @home_directory = File.join(@temporary_directory, "home")
    FileUtils.mkdir_p(File.join(@home_directory, ".claude-container"))
    File.write(File.join(@home_directory, ".claude-container", "oauth-token"), "token")
    # What the user supplies once: the egress CA and the fine-grained GitHub token.
    @sandbox_state = SandboxFixtures.install(@home_directory)
    @podman_state = File.join(@temporary_directory, "podman-state")
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
    Open3.capture3(attach_environment.merge(environment), ATTACH_WORKTREE, *arguments)
  end

  def run_recreate(*arguments)
    Open3.capture3(attach_environment, RECREATE_WORKTREE, *arguments)
  end

  def attach_environment
    {
      "DB_HELPER_DATABASE_PATH" => @database_path,
      "HOME" => @home_directory,
      "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}",
      "STUB_PODMAN_STATE_DIR" => @podman_state,
      "STUB_PODMAN_NFT_LOG" => File.join(@temporary_directory, "nft.log"),
      "STUB_GATEWAY_FINGERPRINT" => gateway_fingerprint
    }
  end

  # The fingerprint of the gateway the helper would build, so the stub's
  # existing gateway counts as current. Blank until the helper exists.
  def gateway_fingerprint
    @gateway_fingerprint ||= begin
      stdout, _, status = Open3.capture3(
        { "HOME" => @home_directory, "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}" },
        SANDBOX_NETWORK, "fingerprint", "--gateway"
      )
      status.success? ? stdout.strip : ""
    rescue Errno::ENOENT
      ""
    end
  end

  # The launch of the agent itself, as opposed to the gateway's `run --detach`.
  def agent_run(calls)
    calls.find { _1.start_with?("run ") && _1.include?("--interactive") }
  end

  def agent_container_name
    "pipelines-claude-matt-#{File.basename(File.realpath(worktree_root))}"
  end

  def agent_state_path
    File.join(@podman_state, "containers", "#{agent_container_name}.json")
  end

  def agent_labels
    JSON.parse(File.read(agent_state_path)).dig("Config", "Labels")
  end

  def set_agent_status(status)
    state = JSON.parse(File.read(agent_state_path))
    state["State"]["Status"] = status
    File.write(agent_state_path, JSON.generate(state))
  end

  # Registers the worktree, attaches it with the podman stub logging its
  # calls, and returns the attach result with the logged podman calls.
  def attach_logging_podman(identifier, environment = {})
    run_helper("register_worktree", identifier, worktree_root, "--ticket=#{identifier}")
    log = File.join(@temporary_directory, "podman.log")
    attached = run_attach(identifier, { "STUB_PODMAN_LOG" => log }.merge(environment))
    [ attached, File.exist?(log) ? File.readlines(log, chomp: true) : [] ]
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
    builds = calls.select { _1.start_with?("build ") }
    build = builds.first

    assert attached.fetch(2).success?, attached.fetch(1)
    assert_equal 1, builds.size, "only the agent image builds while the gateway is current"
    assert_includes build, "--platform linux/amd64"
    assert_match %r{--tag pipelines-claude-matt-agent-amd64:\h{64}}, build
    assert_amd64_run(agent_run(calls))
  end

  # A linked worktree's gitdir points back at the worktree's host path; mounted
  # anywhere else, git and Claude Code's worktree isolation treat it as stale.
  def test_attach_mounts_the_worktree_at_its_host_path
    worktree_path = File.realpath(worktree_root)
    attached, calls = attach_logging_podman("GH-133")
    run = agent_run(calls)

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
    FileUtils.rm_f(agent_state_path) # the first container would be restarted, not relaunched
    run_attach("GH-132", "STUB_PODMAN_LOG" => log, "SANDBOX_MEMORY" => "5g")
    default_run, overridden_run = File.readlines(log, chomp: true).select { _1.start_with?("run ") && _1.include?("--interactive") }

    assert_includes default_run, "--memory 3g"
    assert_includes overridden_run, "--memory 5g"
  end

  private

  def assert_amd64_run(run)
    assert_includes run, "--platform linux/amd64"
    assert_match %r{src=pipelines-claude-matt-[a-z0-9-]+-bundle-amd64,dst=/bundle}, run
    assert_match %r{src=pipelines-claude-matt-[a-z0-9-]+-node-modules-amd64,dst=#{Regexp.escape(File.realpath(worktree_root))}/node_modules}, run
  end
end

class DbHelperAttachOnePasswordTest < Minitest::Test
  include DbHelperTestSupport

  # The host has no 1Password desktop app to mount a .env, so attach reads the
  # Environment with the CLI and passes each secret by name, never by value.
  def test_attach_passes_1password_environment_secrets_by_name
    attached, calls = attach_with_secrets("GH-134", "OPENAI_API_KEY" => "sk-'se cret'$HOME")
    run = agent_run(calls)

    assert attached.fetch(2).success?, attached.fetch(1)
    assert_includes run, "--env OPENAI_API_KEY "
    refute_includes run, "se cret"
    assert_includes podman_environment, "OPENAI_API_KEY=sk-'se cret'$HOME"
  end

  # PEM keys and JSON credentials span lines and often end with a newline.
  def test_attach_passes_a_multi_line_1password_secret_intact
    private_key = "-----BEGIN KEY-----\nline2=foo 'bar'\n-----END KEY-----\n"
    attached, = attach_with_secrets("GH-137", "PRIVATE_KEY" => private_key)

    assert attached.fetch(2).success?, attached.fetch(1)
    assert_includes podman_environment, "PRIVATE_KEY=#{private_key}"
  end

  def test_attach_stops_when_the_1password_environment_cannot_be_read
    attached, calls = attach_with_secrets("GH-135", {}, "STUB_OP_FAILURE" => "true")

    refute attached.fetch(2).success?
    assert_includes attached.fetch(1), "op signin"
    assert_nil(agent_run(calls))
  end

  def test_attach_refuses_an_invalid_1password_secret_name
    attached, calls = attach_with_secrets("GH-138", "BAD-NAME" => "value")

    refute attached.fetch(2).success?
    assert_includes attached.fetch(1), "Invalid 1Password secret name: BAD-NAME"
    assert_nil(agent_run(calls))
  end

  # A secret named like a host variable (PATH, HOME) would change how podman
  # runs once exported.
  def test_attach_refuses_a_1password_secret_that_shadows_a_host_variable
    attached, calls = attach_with_secrets("GH-136", "HOME" => "/tmp/elsewhere")

    refute attached.fetch(2).success?
    assert_includes attached.fetch(1), "HOME"
    assert_nil(agent_run(calls))
  end

  # Unset on the host, BASH_ENV would still make every bash script attach runs
  # -- db_helper among them -- source a file of the secret's choosing.
  def test_attach_refuses_a_1password_secret_that_configures_host_tools
    marker = File.join(@temporary_directory, "bash-env-sourced")
    File.write(bash_env = File.join(@temporary_directory, "bash-env"), "touch #{marker}\n")
    attached, calls = attach_with_secrets("GH-139", "BASH_ENV" => bash_env)

    refute attached.fetch(2).success?
    assert_includes attached.fetch(1), "BASH_ENV"
    refute_path_exists marker
    assert_nil(agent_run(calls))
  end

  # These would override the gateway proxy, the CA bundle or the GitHub token
  # that run-agent sets for the agent.
  def test_attach_refuses_a_1password_secret_that_overrides_the_egress_configuration
    %w[GH_TOKEN HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY OLLAMA_API_BASE SSL_CERT_FILE NODE_EXTRA_CA_CERTS
       CURL_CA_BUNDLE REQUESTS_CA_BUNDLE BUNDLE_SSL_CA_CERT GIT_SSL_CAINFO NODE_USE_ENV_PROXY].each_with_index do |name, index|
      attached, calls = attach_with_secrets("GH-#{200 + index}", name => "override")

      refute attached.fetch(2).success?, "#{name} must be refused"
      assert_includes attached.fetch(1), name
      assert_includes attached.fetch(1), "egress configuration", name
      assert_nil agent_run(calls), name
    end
  end

  def test_attach_refuses_a_lowercase_proxy_secret_as_an_invalid_name
    attached, calls = attach_with_secrets("GH-230", "https_proxy" => "override")

    refute attached.fetch(2).success?
    assert_includes attached.fetch(1), "Invalid 1Password secret name"
    assert_nil agent_run(calls)
  end

  def test_attach_relaunches_the_container_when_a_1password_secret_changes
    launch_configs = { "GH-140" => "old", "GH-141" => "new" }.map do |identifier, value|
      attached, calls = attach_with_secrets(identifier, "API_KEY" => value)
      assert attached.fetch(2).success?, attached.fetch(1)
      calls.reverse.find { _1.start_with?("run ") && _1.include?("--interactive") }[/io\.pipelines\.sandbox\.launch-config=\S+/]
    end

    refute_equal(*launch_configs)
  end

  private

  def attach_with_secrets(identifier, secrets, environment = {})
    attach_logging_podman(
      identifier,
      {
        "SANDBOX_OP_ENVIRONMENT" => "pipelines-dev",
        "STUB_OP_ENVIRONMENTS" => JSON.generate("pipelines-dev" => secrets),
        "STUB_PODMAN_ENV_LOG" => podman_environment_log
      }.merge(environment)
    )
  end

  def podman_environment_log
    File.join(@temporary_directory, "podman-env.log")
  end

  # NAME=value for each variable the podman stub saw passed by name.
  def podman_environment
    File.read(podman_environment_log).split("\0")
  end
end

# Every attach path reconciles the shared egress gateway first, and the agent
# launches through it. The CA and token fixtures live in the temporary HOME.
class DbHelperAttachGatewayTest < Minitest::Test
  include DbHelperTestSupport

  def test_attach_reconciles_the_gateway_before_inspecting_the_container
    attached, calls = attach_logging_podman("GH-150")
    firewall = calls.index { _1.start_with?("machine ssh") }
    status_inspect = calls.index { _1.include?("inspect") && _1.include?(".State.Status") && _1.end_with?(agent_container_name) }

    assert attached.fetch(2).success?, attached.fetch(1)
    assert firewall, "the nft ruleset was never applied: #{calls}"
    assert status_inspect, "the container status was never inspected: #{calls}"
    assert_operator firewall, :<, status_inspect
  end

  def test_attach_restart_and_running_paths_reconcile_first
    attach_logging_podman("GH-151")
    log = File.join(@temporary_directory, "podman.log")

    set_agent_status("exited")
    File.delete(log)
    restarted = run_attach("GH-151", "STUB_PODMAN_LOG" => log)
    restart_calls = File.readlines(log, chomp: true)

    set_agent_status("running")
    File.delete(log)
    reattached = run_attach("GH-151", "STUB_PODMAN_LOG" => log)
    attach_calls = File.readlines(log, chomp: true)

    assert restarted.fetch(2).success?, restarted.fetch(1)
    assert reattached.fetch(2).success?, reattached.fetch(1)
    assert_applied_before(restart_calls, "start --interactive --attach #{agent_container_name}")
    assert_applied_before(attach_calls, "attach #{agent_container_name}")
  end

  def test_attach_launches_through_the_gateway
    environment_log = File.join(@temporary_directory, "podman-env.log")
    attached, calls = attach_logging_podman("GH-152", "STUB_PODMAN_ENV_LOG" => environment_log)
    run = agent_run(calls)
    environment = File.exist?(environment_log) ? File.read(environment_log).split("\0").to_h { _1.split("=", 2) } : {}

    assert attached.fetch(2).success?, attached.fetch(1)
    assert run, "the agent was not launched: #{calls}"
    [
      "--network pipelines-sandbox-net", "--dns=none", "--add-host sandbox-gateway:10.89.7.2",
      "--cap-drop NET_ADMIN", "--cap-drop NET_RAW", "--restart=no", "--http-proxy=false",
      "dst=/run/sandbox-ca.crt,ro"
    ].each { assert_includes run, _1 }
    refute_includes run, "ca-key.pem"
    assert_equal "github_pat_test", environment["GH_TOKEN"]
    assert_match(%r{\Ahttp://nono:\h{64}@sandbox-gateway:3128\z}, environment["HTTPS_PROXY"])
  end

  def test_attach_no_longer_asks_host_gh_for_a_token
    bin = File.join(@temporary_directory, "bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "gh"), "#!/usr/bin/env bash\necho \"$*\" >> \"#{@temporary_directory}/gh-calls\"\nexit 1\n")
    File.chmod(0o755, File.join(bin, "gh"))
    run_helper("register_worktree", "GH-153", worktree_root, "--ticket=GH-153")

    attached = run_attach("GH-153", "PATH" => "#{bin}:#{STUB_BIN}:#{ENV.fetch("PATH")}")

    assert attached.fetch(2).success?, attached.fetch(1)
    refute_path_exists File.join(@temporary_directory, "gh-calls")
    refute_includes attached.fetch(1), "gh auth login"
  end

  def test_attach_launch_config_follows_the_ca_not_the_policy
    attach_logging_podman("GH-154")
    first = agent_labels.fetch("io.pipelines.sandbox.launch-config")

    SandboxFixtures.write_ca(File.join(@sandbox_state, "ca"))
    @gateway_fingerprint = nil
    attached = run_attach("GH-154")
    second = agent_labels.fetch("io.pipelines.sandbox.launch-config")

    assert attached.fetch(2).success?, attached.fetch(1)
    refute_equal first, second, "a new CA must replace the agent"

    # A different gateway fingerprint (policy edit, helper change) recreates
    # the gateway only: the agent keeps its launch config and is restarted.
    log = File.join(@temporary_directory, "podman.log")
    File.delete(log) # the earlier launches also logged a `run --interactive`
    restarted = run_attach("GH-154", "STUB_PODMAN_LOG" => log, "STUB_GATEWAY_FINGERPRINT" => "policy-edited")
    calls = File.readlines(log, chomp: true)

    assert restarted.fetch(2).success?, restarted.fetch(1)
    assert_equal second, agent_labels.fetch("io.pipelines.sandbox.launch-config")
    assert_nil agent_run(calls), "the agent must not be relaunched: #{calls}"
    assert(calls.any? { _1.start_with?("start --interactive --attach") }, calls.inspect)
  end

  def test_attach_refuses_to_launch_without_the_egress_prerequisites
    {
      "missing CA" => -> { FileUtils.rm_rf(File.join(@sandbox_state, "ca")) },
      "CA key readable by others" => -> { File.chmod(0o644, File.join(@sandbox_state, "ca", "ca-key.pem")) },
      "classic GitHub token" => -> { File.write(File.join(@sandbox_state, "gh-token"), "ghp_x\n") },
      "missing GitHub token" => -> { FileUtils.rm_f(File.join(@sandbox_state, "gh-token")) },
      "rootless podman" => { "STUB_PODMAN_ROOTLESS" => "true" },
      "mismatched remote engine" => { "STUB_PODMAN_CONNECTION_URI" => "ssh://root@127.0.0.1:1/run/podman/podman.sock" },
      "unmanaged gateway container" => { "STUB_PODMAN_GATEWAY" => "unmanaged" },
      "unlabelled network" => { "STUB_PODMAN_NETWORK_JSON" => JSON.generate([ unlabelled_network ]) },
      "firewall failure" => { "STUB_FIREWALL_FAILURE" => "true" }
    }.each_with_index do |(description, breakage), index|
      identifier = "GH-#{160 + index}"
      FileUtils.rm_rf(@podman_state)
      SandboxFixtures.install(@home_directory)
      environment = breakage.is_a?(Hash) ? breakage : (breakage.call && {})

      attached, calls = attach_logging_podman(identifier, environment)

      refute attached.fetch(2).success?, "#{description}: attach must refuse"
      assert_nil agent_run(calls), "#{description}: nothing may be launched"
      assert_equal "created\n", run_helper("get_container_status", identifier, "--profile=claude-matt").first, description
      File.delete(File.join(@temporary_directory, "podman.log")) if File.exist?(File.join(@temporary_directory, "podman.log"))
    end
  end

  def test_attach_refuses_the_reserved_sandbox_profile
    run_helper("register_worktree", "GH-170", worktree_root, "--ticket=GH-170")

    attached = run_attach("GH-170", "--profile=sandbox")

    refute attached.fetch(2).success?
    assert_includes attached.fetch(1), "reserved"
  end

  def test_recreate_worktree_refuses_the_reserved_sandbox_profile
    run_helper("register_worktree", "GH-171", worktree_root, "--ticket=GH-171")

    recreated = run_recreate("GH-171", "--profile=sandbox", "--dry-run")

    refute recreated.fetch(2).success?
    assert_includes recreated.fetch(1), "reserved"
  end

  def test_register_container_refuses_the_reserved_sandbox_profile
    register_issue_worktree("GH-172", File.join(@temporary_directory, "gh-172"))

    registered = run_helper("register_container", "GH-172", "sandbox")
    status = run_helper("get_container_status", "GH-172", "--profile=sandbox")

    refute registered.fetch(2).success?
    assert_includes registered.fetch(1), "reserved"
    refute status.fetch(2).success?, "nothing may be registered under the reserved profile"
  end

  private

  def unlabelled_network
    {
      "name" => "pipelines-sandbox-net", "network_interface" => "podman7", "internal" => false, "dns_enabled" => false,
      "subnets" => [ { "subnet" => "10.89.7.0/24", "gateway" => "10.89.7.1" } ], "containers" => {}
    }
  end

  def assert_applied_before(calls, launch)
    firewall = calls.index { _1.start_with?("machine ssh") }
    action = calls.index(launch)

    assert action, "expected `podman #{launch}`, got #{calls}"
    assert firewall, "the nft ruleset was never applied: #{calls}"
    assert_operator firewall, :<, action
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

  def test_cleanup_finished_removes_the_dependency_volumes_of_a_finished_container
    worktree_path = register_issue_worktree("GH-140", sandbox_worktree_path("gh-140"))
    register_container("GH-140", "claude-omcc", "finished")
    container = "pipelines-claude-omcc-gh-140"
    kept = [ "#{container}-other-bundle-amd64", "pipelines-claude-omcc-home", "pipelines-sandbox-pnpm-store" ]
    removed = %W[#{container}-bundle-amd64 #{container}-node-modules-amd64 #{container}-bundle #{container}-node-modules]

    cleaned = cleanup_finished(worktree_path, "STUB_PODMAN_LOG" => podman_log, "STUB_PODMAN_VOLUMES" => (removed + kept).join(","))

    removed.each { |volume| assert_includes cleaned, "Removing sandbox volume: #{volume}" }
    assert_equal removed.sort, podman_calls.grep(/\Avolume rm /).map { _1.split.last }.sort
  end

  def test_cleanup_finished_leaves_a_sibling_worktrees_volumes_alone
    worktree_path = register_issue_worktree("GH-140", sandbox_worktree_path("gh-140"))
    register_container("GH-140", "claude-omcc", "finished")
    sibling = "pipelines-claude-omcc-gh-1400"

    cleanup_finished(worktree_path, "STUB_PODMAN_LOG" => podman_log,
                                    "STUB_PODMAN_VOLUMES" => "#{sibling}-bundle-amd64,#{sibling}-node-modules")

    assert_empty podman_calls.grep(/\Avolume rm /)
  end

  def test_cleanup_finished_succeeds_with_nothing_to_clean_while_podman_is_down
    stdout, stderr, status = run_helper("cleanup_finished", "STUB_PODMAN_DOWN" => "true")

    assert status.success?, stderr
    assert_equal "No finished sandbox containers.\n", stdout
    assert_includes stderr, "skipping unused image cleanup"
  end

  def test_cleanup_finished_removes_agent_images_that_no_container_uses
    images = %w[
      localhost/pipelines-claude-matt-agent-amd64:old localhost/pipelines-claude-matt-agent-amd64:used
      localhost/pipelines-claude-omcc-agent:verify localhost/pipelines-sandbox-gateway:abc
      localhost/propstack-codex-matt-agent:x
    ]

    stdout, stderr, status = run_helper(
      "cleanup_finished",
      "STUB_PODMAN_LOG" => podman_log, "STUB_PODMAN_IMAGES" => images.join(","),
      "STUB_PODMAN_IMAGE_USERS" => "localhost/pipelines-claude-matt-agent-amd64:used=pipelines-claude-matt-gh-1"
    )

    assert status.success?, stderr
    assert_includes stdout, "Keeping image still used by pipelines-claude-matt-gh-1: localhost/pipelines-claude-matt-agent-amd64:used"
    assert_equal %w[localhost/pipelines-claude-matt-agent-amd64:old localhost/pipelines-claude-omcc-agent:verify],
                 podman_calls.grep(/\Aimage rm /).map { _1.split.last }
  end

  private

  def podman_log
    @podman_log ||= File.join(@temporary_directory, "podman.log")
  end

  def podman_calls
    File.exist?(podman_log) ? File.readlines(podman_log, chomp: true) : []
  end

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
