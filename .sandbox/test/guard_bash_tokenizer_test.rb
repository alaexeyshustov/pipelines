require "minitest/autorun"
require "json"
require "open3"

# Tokenizer holes in guard-bash found by comparing verdicts with what bash runs.
# Outcomes: :allow, :ask, :block (see guard_bash_test.rb).
class GuardBashTokenizerTest < Minitest::Test
  GUARD = File.expand_path("../profiles/lib/claude/hooks/guard-bash", __dir__)

  CASES = {
    # `<<` in arithmetic is a shift, not a heredoc; an unterminated heredoc must
    # not hide the rest. CRLF: bash takes the delimiter as `EOF\r`, which matches
    # the `EOF\r` line, so `git reset --hard` really runs -> block.
    "heredoc_blocks" => [
      [ "echo $((1<<2))\ngit reset --hard", :block ],
      [ "(( x = 1<<2 ))\ngit push --force", :block ],
      [ "cat <<'EOF'\r\nx\r\nEOF\r\ngit reset --hard ;\r\n", :block ],
      [ "cat <<$'EOF'\nx\nEOF\ngit reset --hard", :block ]
    ],
    "heredoc_asks" => [
      [ "cat <<EOF\nx\ngit reset --hard", :ask ]
    ],
    "heredoc_allows" => [
      [ "echo $((1<<2))", :allow ],
      [ "cat <<EOF\nx\nEOF\ngit status", :allow ]
    ],
    # `\'` does not end an ANSI-C string.
    "ansi_c_blocks" => [
      [ "echo $'\\'' && git reset --hard #'", :block ],
      [ "echo $'it\\'s' ; git push --force ; echo $'\\''", :block ]
    ],
    "ansi_c_allows" => [
      [ "echo $'it\\'s fine'", :allow ]
    ],
    # Escaped backticks inside backticks are nested code.
    "backtick_asks" => [
      [ "echo `echo \\`git reset --hard\\``", :ask ]
    ],
    "backtick_allows" => [
      [ "echo `echo \\`git status\\``", :allow ]
    ],
    # Redirections with & or <> before the command word.
    "redirect_blocks" => [
      [ "0<&- git reset --hard", :block ],
      [ "<&0 git push --force", :block ],
      [ "2>&1 git reset --hard", :block ],
      [ "<> f git reset --hard", :block ]
    ],
    "redirect_asks" => [
      [ ">&2 git push", :ask ]
    ],
    # Decision: the last-resort text scan keeps asking on quoted mentions.
    "quoted_mention_asks" => [
      [ 'rg "git push" docs/', :ask ],
      [ 'grep -rn "gh pr merge" .sandbox', :ask ],
      [ 'git commit -m "Mention gh pr merge in docs"', :ask ]
    ]
  }.freeze

  CASES.each do |group, cases|
    cases.each_with_index do |(command, outcome), index|
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

  def run_guard(command)
    Open3.capture3(GUARD, stdin_data: JSON.generate(tool_name: "Bash", tool_input: { command: command }), binmode: true)
  end
end
