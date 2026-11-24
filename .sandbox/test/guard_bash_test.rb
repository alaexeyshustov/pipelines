require "minitest/autorun"
require "json"
require "open3"

# guard-bash is a Claude Code PreToolUse hook. Block = exit 2 + reason on
# stderr; ask = exit 0 + permissionDecision JSON on stdout; allow = exit 0
# with no output.
class GuardBashTest < Minitest::Test
  GUARD = File.expand_path("../profiles/lib/claude/hooks/guard-bash", __dir__)

  BLOCKED = [
    "git push --force",
    "git push -f",
    "git push --force origin main",
    "git push origin main --force",
    "git push -f origin feat/x",
    "git -C /w push -f",
    "git -C /w push --force origin main",
    "git -c core.pager=cat push -f",
    "git --no-pager push --force",
    "git reset --hard",
    "git reset --hard origin/main",
    "git -C /w reset --hard HEAD~1",
    "git clean -f",
    "git clean -fd",
    "git clean -xfd",
    "git clean -fdx",
    "git branch -D feat/x",
    "git -C /w branch -D old",
    "git checkout .",
    "git checkout -- .",
    "git restore .",
    "cd a && git push --force",
    "cd a; git reset --hard",
    "true || git clean -fd",
    "echo hi | git push -f",
    "echo $(git reset --hard)",
    "echo `git reset --hard`",
    "(git push -f)",
    "ls\ngit reset --hard",
    "rtk git push --force",
    "rtk git reset --hard",
    "FOO=1 git push -f",
    "env GIT_TRACE=1 git push -f",
    "sudo git reset --hard",
    "command git clean -fd",
    "exec git push --force"
  ].freeze

  ASKED = [
    "git push",
    "git push origin main",
    "git push -u origin feat/x",
    "git push --force-with-lease",
    "git push --force-with-lease origin main",
    "git push origin +main",
    "git push origin +HEAD:main",
    "git -C /w push",
    "cd a && git push",
    "rtk git push",
    "gh pr comment 1 --body hi",
    "gh pr create --title t --body b",
    "gh pr merge 1",
    "gh pr review 1 --approve",
    "gh pr edit 1 --title x",
    "gh pr close 1",
    "gh pr ready 1",
    "gh pr reopen 1",
    "gh issue comment 1 --body hi",
    "gh issue create --title t",
    "gh issue close 1",
    "gh issue delete 1",
    "gh issue transfer 1 owner/repo",
    "gh issue lock 1",
    "gh release create v1",
    "gh release delete v1",
    "gh repo create foo",
    "gh repo delete foo",
    "gh workflow run ci.yml",
    "gh label create bug",
    "gh secret set FOO",
    "gh variable set FOO",
    "rtk gh pr comment 1 --body hi",
    "cd a && gh pr merge 1",
    "gh api repos/o/r/issues -f title=t",
    "gh api repos/o/r/issues -F title=t",
    "gh api repos/o/r/issues --field title=t",
    "gh api repos/o/r/issues --raw-field title=t",
    "gh api repos/o/r/issues --input body.json",
    "gh api -X POST repos/o/r/issues",
    "gh api --method DELETE repos/o/r/issues/1",
    "gh api -X PATCH repos/o/r/issues/1",
    "gh api graphql -f query='mutation { x }'",
    "gh api graphql -F query=@q.graphql",
    "gh pr comment 1 --body \"unterminated"
  ].freeze

  ALLOWED = [
    "ls -la",
    "git status",
    "git log -1",
    "git diff",
    "git fetch origin",
    "git commit -m wip",
    "git branch -d merged",
    "git branch --list",
    "git clean -n",
    "git clean -nd",
    "git reset --soft HEAD~1",
    "git reset HEAD file",
    "git checkout main",
    "git checkout -b feat/x",
    "git checkout -- file.rb",
    "git restore file.rb",
    "git stash",
    "git pull",
    "rtk git status",
    "bundle exec rspec",
    "echo \"git reset --hard is blocked\"",
    "grep -r 'git clean -fd' docs",
    "gh pr view 1",
    "gh pr list",
    "gh pr diff 1",
    "gh pr status",
    "gh pr checks 1",
    "gh issue view 1",
    "gh issue list",
    "gh issue status",
    "gh search issues foo",
    "gh run view 1",
    "gh release view v1",
    "gh repo view",
    "gh api repos/o/r/issues",
    "gh api -X GET repos/o/r/issues",
    "gh api --method GET repos/o/r/issues",
    "rtk gh pr view 1",
    "cd a && gh pr view 1",
    "cd a && git status"
  ].freeze

  # Nested or indirect forms the parser cannot see into. Fail closed: raw text
  # mentioning git push or a gh write asks (never allows, never blocks).
  NESTED_ASKED = [
    "echo \"$(git push)\"",
    "echo \"$(git push --force)\"",
    "echo \"$(git push -f origin main)\"",
    "echo \"`git push`\"",
    "x=\"`git push --force`\"",
    "x=\"`gh pr comment 1 -b hi`\"",
    "echo \"$(gh pr comment 1 -b hi)\"",
    "echo \"$(gh pr merge 1)\"",
    "echo \"$(gh pr create --title t)\"",
    "echo \"$(gh api -X POST repos/o/r/issues)\"",
    "bash -c \"git push\"",
    "bash -c 'git push'",
    "bash -c 'git push --force'",
    "bash -c \"git push -f origin main\"",
    "sh -c 'git push'",
    "sh -c \"git push --force\"",
    "zsh -c 'git push'",
    "zsh -c \"git push -f\"",
    "bash -c 'gh pr comment 1 -b hi'",
    "bash -c \"gh pr merge 1\"",
    "sh -c 'gh pr create --title t'",
    "zsh -c \"gh api -X POST repos/o/r/issues\"",
    "bash -c 'cd a && git push'",
    "eval \"git push\"",
    "eval 'git push --force'",
    "eval \"gh pr merge 1\"",
    "eval 'gh pr comment 1 -b hi'",
    "eval \"gh pr create --title t\"",
    "eval 'gh api -X POST repos/o/r/issues'",
    "echo origin | xargs git push",
    "echo origin | xargs git push --force",
    "echo 1 | xargs gh pr merge",
    "echo 1 | xargs -I{} gh pr comment {} -b hi",
    "env bash -c 'git push'",
    "env bash -c \"git push --force\"",
    "env FOO=1 sh -c 'gh pr merge 1'",
    "sudo bash -c 'gh issue create --title t'",
    "echo \"gh pr merge is asked\"",
    "echo 'git push --force is blocked'"
  ].freeze

  # Reads and plain commands must not be caught by the fail-closed rule.
  NESTED_ALLOWED = [
    "bash -c \"gh issue view 1\"",
    "bash -c 'gh pr list'",
    "sh -c 'git status'",
    "zsh -c \"git log -1\"",
    "eval \"git status\"",
    "eval 'gh pr view 1'",
    "echo \"$(git status)\"",
    "echo \"`git log -1`\"",
    "echo \"$(gh pr view 1)\"",
    "echo \"$(gh api repos/o/r/issues)\"",
    "echo origin | xargs git fetch",
    "echo 1 | xargs gh pr view",
    "env bash -c 'ls -la'",
    "echo \"git reset --hard is blocked\"",
    "echo \"gh issue view is allowed\""
  ].freeze

  BLOCKED.each_with_index do |command, index|
    define_method("test_blocks_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
      stdout, stderr, status = run_guard(command)

      assert_equal 2, status.exitstatus, "expected block for #{command.inspect}: #{stdout} #{stderr}"
      refute_empty stderr.strip, "block must explain itself on stderr"
      assert_empty stdout
    end
  end

  ASKED.each_with_index do |command, index|
    define_method("test_asks_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
      stdout, stderr, status = run_guard(command)

      assert_equal 0, status.exitstatus, "expected ask for #{command.inspect}: #{stderr}"
      output = JSON.parse(stdout)["hookSpecificOutput"]
      assert_equal "PreToolUse", output["hookEventName"]
      assert_equal "ask", output["permissionDecision"], "expected ask for #{command.inspect}"
      refute_empty output["permissionDecisionReason"].to_s
    end
  end

  ALLOWED.each_with_index do |command, index|
    define_method("test_allows_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
      stdout, stderr, status = run_guard(command)

      assert_equal 0, status.exitstatus, "expected allow for #{command.inspect}: #{stderr}"
      assert_empty stdout, "allow must print nothing for #{command.inspect}"
    end
  end

  NESTED_ASKED.each_with_index do |command, index|
    define_method("test_nested_asks_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
      stdout, stderr, status = run_guard(command)

      assert_equal 0, status.exitstatus, "expected ask (not block) for #{command.inspect}: #{stderr}"
      refute_empty stdout, "expected ask for #{command.inspect}, got allow"
      output = JSON.parse(stdout)["hookSpecificOutput"]
      assert_equal "ask", output["permissionDecision"], "expected ask for #{command.inspect}"
      refute_empty output["permissionDecisionReason"].to_s
    end
  end

  NESTED_ALLOWED.each_with_index do |command, index|
    define_method("test_nested_allows_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
      stdout, stderr, status = run_guard(command)

      assert_equal 0, status.exitstatus, "expected allow for #{command.inspect}: #{stderr}"
      assert_empty stdout, "allow must print nothing for #{command.inspect}"
    end
  end

  def test_force_with_lease_asks_rather_than_blocks
    _, _, status = run_guard("git push --force-with-lease")

    refute_equal 2, status.exitstatus
  end

  def test_non_bash_tool_is_allowed
    stdout, _, status = run_payload(JSON.generate(tool_name: "Read", tool_input: { file_path: "/tmp/x" }))

    assert_equal 0, status.exitstatus
    assert_empty stdout
  end

  def test_missing_command_is_allowed
    stdout, _, status = run_payload(JSON.generate(tool_name: "Bash", tool_input: {}))

    assert_equal 0, status.exitstatus
    assert_empty stdout
  end

  GH_GLOBAL_PREFIXES = ["-R o/r", "--repo o/r", "--repo=o/r", "-Ro/r", "--hostname h"].freeze
  GH_WRITE_TAILS = ["issue comment 1 -b x", "pr merge 1", "pr create --title t", "api -X POST repos/o/r/issues"].freeze
  GH_READ_TAILS = ["issue view 1", "pr list"].freeze
  GH_CONTEXTS = [
    ->(cmd) { cmd },
    ->(cmd) { "bash -c \"#{cmd}\"" },
    ->(cmd) { "eval \"#{cmd}\"" },
    ->(cmd) { "echo \"$(#{cmd})\"" }
  ].freeze

  DESTRUCTIVE_GIT = [
    "git reset --hard", "git clean -f", "git clean -fd", "git branch -D x", "git checkout .", "git restore ."
  ].freeze
  GIT_NEST_CONTEXTS = [
    ->(cmd) { "bash -c '#{cmd}'" },
    ->(cmd) { "sh -c '#{cmd}'" },
    ->(cmd) { "eval \"#{cmd}\"" },
    ->(cmd) { "echo \"$(#{cmd})\"" },
    ->(cmd) { "echo \"`#{cmd}`\"" },
    ->(cmd) { "echo x | xargs #{cmd}" }
  ].freeze

  # Extra cases by group. Expected outcome is the plan's intent.
  GH_GLOBAL_ASKED = GH_GLOBAL_PREFIXES.product(GH_WRITE_TAILS, GH_CONTEXTS).map do |prefix, tail, context|
    context.call("gh #{prefix} #{tail}")
  end.freeze
  GH_GLOBAL_ALLOWED = GH_GLOBAL_PREFIXES.product(GH_READ_TAILS, GH_CONTEXTS).map do |prefix, tail, context|
    context.call("gh #{prefix} #{tail}")
  end.freeze

  NESTED_DESTRUCTIVE_ASKED = DESTRUCTIVE_GIT.product(GIT_NEST_CONTEXTS).map { |cmd, context| context.call(cmd) }.freeze
  NESTED_SAFE_GIT_ALLOWED = [
    "bash -c 'git reset --soft HEAD~1'",
    "eval \"git clean -n\"",
    "sh -c 'git branch -d merged'",
    "bash -c 'git checkout main'",
    "echo \"$(git restore file.rb)\"",
    "echo x | xargs git clean -n"
  ].freeze

  QUOTED_GLOBAL_ASKED = [
    "git -C \"a b\" push",
    "bash -c 'git -C \"a b\" push'",
    "eval \"git -C 'a b' push\""
  ].freeze
  QUOTED_GLOBAL_BLOCKED = [
    "git -c \"user.name=x y\" push --force",
    "git -C \"a b\" push -f"
  ].freeze

  EDGE_ASKED = [
    "git push \\",
    "echo \"a\\\"b\" && git push",
    "# x\ngit push",
    "gh api repos/o/r/issues --method=POST",
    "gh api repos/o/r/issues --method POST",
    "gh api repos/o/r/issues -XPOST",
    "gh api repos/o/r/issues --field=a=b",
    "gh api repos/o/r/issues --raw-field=a=b",
    "gh api repos/o/r/issues --input=f",
    "bash -c 'gh api -X POST repos/o/r/issues'"
  ].freeze
  EDGE_ALLOWED = [
    "echo a\\ b",
    "git\\ push",
    "echo a\\",
    "# git push",
    "git status # git push",
    "echo a#b",
    "git commit -m \"fix push bug\"",
    "gh api repos/o/r/issues -X GET",
    "gh api repos/o/r/issues --method=GET",
    "bash -c 'gh api -X GET repos/o/r/issues'",
    "eval \"gh api --method=GET repos/o/r/issues\""
  ].freeze

  {
    "gh_global_asks" => [GH_GLOBAL_ASKED, :ask],
    "nested_destructive_asks" => [NESTED_DESTRUCTIVE_ASKED, :ask],
    "quoted_global_asks" => [QUOTED_GLOBAL_ASKED, :ask],
    "edge_asks" => [EDGE_ASKED, :ask],
    "gh_global_allows" => [GH_GLOBAL_ALLOWED, :allow],
    "nested_safe_git_allows" => [NESTED_SAFE_GIT_ALLOWED, :allow],
    "edge_allows" => [EDGE_ALLOWED, :allow],
    "quoted_global_blocks" => [QUOTED_GLOBAL_BLOCKED, :block]
  }.each do |group, (commands, outcome)|
    commands.each_with_index do |command, index|
      define_method("test_#{group}_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
        assert_outcome outcome, run_guard(command), command
      end
    end
  end

  def test_empty_stdin_is_allowed
    assert_outcome :allow, run_payload(""), "empty stdin"
  end

  def test_non_json_without_git_or_gh_is_allowed
    assert_outcome :allow, run_payload("hello world"), "non-json plain"
  end

  def test_non_json_with_git_push_asks
    assert_outcome :ask, run_payload("not json: git push origin"), "non-json git push"
  end

  def test_json_null_is_allowed
    assert_outcome :allow, run_payload("null"), "json null"
  end

  def test_non_bash_tool_with_push_command_is_allowed
    payload = JSON.generate(tool_name: "Read", tool_input: { command: "git push" })
    assert_outcome :allow, run_payload(payload), "non-Bash tool"
  end

  def test_non_string_command_is_allowed
    payload = JSON.generate(tool_name: "Bash", tool_input: { command: ["git", "push"] })
    assert_outcome :allow, run_payload(payload), "array command"
  end

  def test_missing_tool_input_is_allowed
    assert_outcome :allow, run_payload(JSON.generate(tool_name: "Bash")), "no tool_input"
  end

  private

  def assert_outcome(outcome, result, label)
    stdout, stderr, status = result
    case outcome
    when :allow
      assert_equal 0, status.exitstatus, "expected allow for #{label}: #{stderr}"
      assert_empty stdout, "expected allow for #{label}, got #{stdout}"
    when :ask
      assert_equal 0, status.exitstatus, "expected ask (not block) for #{label}: #{stderr}"
      refute_empty stdout, "expected ask for #{label}, got allow"
      assert_equal "ask", JSON.parse(stdout).dig("hookSpecificOutput", "permissionDecision"), "expected ask for #{label}"
    when :block
      assert_equal 2, status.exitstatus, "expected block for #{label}: #{stdout} #{stderr}"
      refute_empty stderr.strip
    end
  end

  def run_guard(command)
    run_payload(JSON.generate(tool_name: "Bash", tool_input: { command: command }))
  end

  def run_payload(payload)
    Open3.capture3(GUARD, stdin_data: payload)
  end
end
