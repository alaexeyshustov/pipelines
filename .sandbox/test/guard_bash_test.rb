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
    "echo 'git push --force is blocked'",
    "echo \"gh pr merge is asked\"",
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

  private

  def run_guard(command)
    run_payload(JSON.generate(tool_name: "Bash", tool_input: { command: command }))
  end

  def run_payload(payload)
    Open3.capture3(GUARD, stdin_data: payload)
  end
end
