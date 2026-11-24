require "minitest/autorun"
require "json"
require "open3"
require "benchmark"

# Hardening pins for guard-bash: fail closed, gh allowlist, looser git/command
# matching, heredocs as data. Outcomes: :allow, :ask, :block (see guard_bash_test.rb).
class GuardBashHardeningTest < Minitest::Test
  GUARD = File.expand_path("../profiles/lib/claude/hooks/guard-bash", __dir__)

  def self.nest_subshell(leaf, depth)
    depth.times.reduce(leaf) { |inner, _| %(bash -c "$(#{inner})") }
  end

  # 1. Fail closed ---------------------------------------------------------
  FAIL_CLOSED_COMMANDS = {
    "eval_2000_deep_push" => ("eval " * 2000) + "git push",
    "bash_c_25_deep_push" => nest_subshell("git push", 25),
    "bash_c_25_deep_reset" => nest_subshell("git reset --hard", 25),
    "bash_c_25_deep_benign" => nest_subshell("git status", 25)
  }.freeze

  FAIL_CLOSED_COMMANDS.each do |name, command|
    define_method("test_fail_closed_#{name}") do
      assert_outcome :ask, run_guard(command), name
    end
  end

  def test_fail_closed_tool_input_is_a_string
    payload = JSON.generate(tool_name: "Bash", tool_input: "git push --force")
    assert_outcome :ask, run_payload(payload), "tool_input string"
  end

  def test_fail_closed_payload_is_json_array
    assert_outcome :ask, run_payload(JSON.generate([{ tool_name: "Bash", tool_input: { command: "git push" } }])), "array payload"
  end

  def test_fail_closed_invalid_utf8_under_lang_c
    payload = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push \xFF\xFE origin\"}}".b
    assert_outcome :ask, run_payload(payload, env: { "LANG" => "C", "LC_ALL" => "C" }), "invalid bytes"
  end

  def test_fail_closed_invalid_utf8_reset_hard_under_lang_c
    payload = "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git reset --hard \xFF\"}}".b
    assert_outcome :ask, run_payload(payload, env: { "LANG" => "C", "LC_ALL" => "C" }), "invalid bytes reset"
  end

  def test_valid_em_dash_next_to_reset_hard_blocks_under_lang_c
    result = run_guard("echo \"a — b\"; git reset --hard", env: { "LANG" => "C", "LC_ALL" => "C" })
    assert_outcome :block, result, "em-dash + reset --hard under LANG=C"
  end

  def test_valid_em_dash_benign_allows_under_lang_c
    assert_outcome :allow, run_guard("echo \"a — b\"", env: { "LANG" => "C", "LC_ALL" => "C" }), "em-dash benign"
  end

  def test_deep_eval_chain_is_fast_and_asks
    result = nil
    elapsed = Benchmark.realtime { result = run_guard(("eval " * 20_000) + "git push") }
    assert_outcome :ask, result, "20000-deep eval"
    assert_operator elapsed, :<, 2.0, "20000-deep eval chain took #{elapsed.round(2)}s"
  end

  # 2. gh allowlist --------------------------------------------------------
  GH_ALLOWED = [
    "gh issue view 1", "gh issue list", "gh issue status", "gh pr view 1", "gh pr list",
    "gh pr diff 1", "gh pr status", "gh pr checks 1", "gh search issues foo", "gh search prs foo",
    "gh search code foo", "gh run view 1", "gh run list", "gh run watch 1", "gh release view v1",
    "gh release list", "gh repo view", "gh api repos/a/b", "gh api -X GET repos/a/b",
    "gh auth status", "gh --version", "gh help", "gh -R o/r pr view 1", "gh --repo=o/r pr list"
  ].freeze

  GH_ASKED = [
    "gh pr revert 1", "gh gist create f", "gh project item-add", "gh cache delete --all",
    "gh ssh-key add k", "gh gpg-key add k", "gh repo autolink create", "gh alias set m 'pr merge'",
    "gh m", "gh extension install x/y", "gh api repos/a/b -fx=1", "gh api repos/a/b -Fbody=@x",
    "/usr/bin/gh pr merge 1", "/usr/local/bin/gh pr create --title t", "gh pr checkout 1",
    "gh repo clone a/b", "gh workflow list", "gh codespace create", "gh auth login",
    "gh auth refresh", "gh repo fork a/b", "gh run rerun 1", "gh run cancel 1",
    "gh gist list", "gh label list", "gh unknown-subcommand", "gh extension exec foo",
    "bash -c 'gh gist create f'"
  ].freeze

  # 3. Looser git / command matching --------------------------------------
  CMD_BLOCKED = [
    "/usr/bin/git push --force", "/usr/bin/git reset --hard", "/usr/local/bin/git clean -fd",
    "git --literal-pathspecs push --force", "git --exec-path=/x push -f", "git --no-lazy-fetch reset --hard",
    "git --exec-path /x reset --hard", "git --git-dir /g push -f", "git --git-dir=/g push -f",
    "git --work-tree /w reset --hard", "git --namespace n push -f", "git --config-env cfg=VAR push -f",
    "git -C /w --literal-pathspecs push --force", "git --no-optional-locks --no-pager reset --hard",
    "time git reset --hard", "nohup git push -f", "nice git push --force", "nice -n 5 git push --force",
    "timeout 5 git reset --hard", "timeout -s KILL 5 git reset --hard", "timeout --signal=KILL 5s git push -f",
    "builtin git reset --hard", "rtk proxy git push --force", "sudo -u root git branch -D x",
    "sudo -g wheel git reset --hard", "env -u FOO git push --force", "env -C /w git push -f",
    "exec -a name git push --force", "sudo -u root /usr/bin/git push -f"
  ].freeze
  CMD_ASKED = [
    "/bin/bash -c 'git reset --hard'", "/usr/bin/env bash -c 'git push'", "git --glob-pathspecs push",
    "git --no-lazy-fetch push", "time git push", "nice -n 5 git push", "timeout 5 git push",
    "sudo -u root git push", "rtk proxy git push", "env -u FOO git push", "/usr/bin/git push"
  ].freeze
  CMD_ALLOWED = [
    "git --no-pager status", "git --literal-pathspecs status", "time git status", "timeout 5 git log -1",
    "nice -n 5 git diff", "sudo -u root git status", "rtk proxy git status", "env -u FOO git status",
    "/usr/bin/git status"
  ].freeze

  # 4. Heredocs are data ---------------------------------------------------
  HD_BLOCKED = [
    "git reset --hard && cat <<'EOF'\nit's\nEOF",
    "git push --force && cat <<'EOF'\nit's\nEOF",
    "git push --force && cat <<-EOF\n\tit's\n\tEOF",
    "git reset --hard && cat <<EOF\nit's\nEOF",
    "cat <<'EOF'\nit's\nEOF\ngit reset --hard"
  ].freeze
  HD_ASKED = [
    "git push && cat <<'EOF'\nit's\nEOF",
    "git push && cat <<-EOF\n\tit's\n\tEOF",
    "git push && cat <<EOF\nit's\nEOF",
    "gh pr create --body \"$(cat <<'EOF'\nIt's done\nEOF\n)\"",
    "gh pr create --body \"$(cat <<EOF\nIt's done\nEOF\n)\"",
    "gh pr create --body \"$(cat <<-EOF\n\tIt's done\n\tEOF\n)\""
  ].freeze
  HD_ALLOWED = [
    "cat > s.sh <<'EOF'\ngit reset --hard\nEOF",
    "cat > s.sh <<EOF\ngit reset --hard\nEOF",
    "cat > s.sh <<-EOF\n\tgit push --force\n\tEOF",
    "cat > notes.md <<'EOF'\ngh pr merge 1\nit's a \"quote\nEOF",
    "git commit -F - <<'EOF'\nfix: don't run git clean -fd\nEOF"
  ].freeze

  UNPARSEABLE_ASKED = [
    "echo \"oops git reset --hard",
    "echo 'x git clean -fd",
    "echo \"git branch -D y",
    "echo \"git checkout . ",
    "echo 'git restore .",
    "echo \"git push",
    "echo 'gh pr merge 1",
    "echo \"$(gh issue view 1",
    "not json: git reset --hard"
  ].freeze

  # Minor fixes ------------------------------------------------------------
  MINOR_ALLOWED = ["git restore --staged .", "git clean -n -f", "git clean -fn", "git clean --dry-run -f"].freeze
  MINOR_ASKED = ["git push -- -f"].freeze
  MINOR_BLOCKED = [
    "git branch --delete --force x", "git branch -d -f x", "git branch -f -d x",
    "git checkout -f", "git checkout HEAD .", "git restore :/"
  ].freeze

  {
    "gh_allowlist_allows" => [GH_ALLOWED, :allow],
    "gh_allowlist_asks" => [GH_ASKED, :ask],
    "cmd_blocks" => [CMD_BLOCKED, :block],
    "cmd_asks" => [CMD_ASKED, :ask],
    "cmd_allows" => [CMD_ALLOWED, :allow],
    "heredoc_blocks" => [HD_BLOCKED, :block],
    "heredoc_asks" => [HD_ASKED, :ask],
    "heredoc_allows" => [HD_ALLOWED, :allow],
    "unparseable_asks" => [UNPARSEABLE_ASKED, :ask],
    "minor_allows" => [MINOR_ALLOWED, :allow],
    "minor_asks" => [MINOR_ASKED, :ask],
    "minor_blocks" => [MINOR_BLOCKED, :block]
  }.each do |group, (commands, outcome)|
    commands.each_with_index do |command, index|
      define_method("test_#{group}_#{index}_#{command.gsub(/\W+/, "_")[0, 40]}") do
        assert_outcome outcome, run_guard(command), command
      end
    end
  end

  private

  def assert_outcome(outcome, result, label)
    stdout, stderr, status = result
    code = status.exitstatus
    case outcome
    when :allow
      assert_equal 0, code, "expected allow for #{label.inspect}: exit #{code.inspect} #{stderr.lines.first}"
      assert_empty stdout, "expected allow for #{label.inspect}, got #{stdout}"
    when :ask
      assert_equal 0, code, "expected ask for #{label.inspect}: exit #{code.inspect} #{stderr.lines.first}"
      refute_empty stdout, "expected ask for #{label.inspect}, got allow"
      assert_equal "ask", JSON.parse(stdout).dig("hookSpecificOutput", "permissionDecision"), "expected ask for #{label.inspect}"
    when :block
      assert_equal 2, code, "expected block for #{label.inspect}: exit #{code.inspect} #{stdout} #{stderr.lines.first}"
      refute_empty stderr.strip
    end
  end

  def run_guard(command, env: {})
    run_payload(JSON.generate(tool_name: "Bash", tool_input: { command: command }), env: env)
  end

  def run_payload(payload, env: {})
    Open3.capture3(env, GUARD, stdin_data: payload, binmode: true)
  end
end
