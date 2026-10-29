require "minitest/autorun"
require "open3"
require "tmpdir"

class SessionCommonTest < Minitest::Test
  SESSION_COMMON = File.expand_path("../profiles/lib/session-common.sh", __dir__)

  def test_dependency_fingerprint_tolerates_missing_files
    Dir.mktmpdir("session-common-test") do |workspace|
      File.write(File.join(workspace, "Gemfile"), "source 'https://rubygems.org'\n")

      stdout, stderr, status = run_bash(<<~'SH', workspace)
        fingerprint="$(dependency_fingerprint Gemfile Gemfile.lock .bundle/config)"
        printf 'fingerprint=%s\n' "$fingerprint"
      SH

      assert status.success?, "session aborted under set -e: #{stderr}"
      assert_match(/\Afingerprint=\h{64}\n\z/, stdout)
    end
  end

  def test_dependency_fingerprint_changes_with_file_contents
    Dir.mktmpdir("session-common-test") do |workspace|
      gemfile = File.join(workspace, "Gemfile")
      script = %q(dependency_fingerprint Gemfile .bundle/config)

      File.write(gemfile, "a\n")
      first, = run_bash(script, workspace)
      File.write(gemfile, "b\n")
      second, = run_bash(script, workspace)

      refute_equal first, second
    end
  end

  def test_exec_claude_leaves_text_selection_to_the_host_terminal
    Dir.mktmpdir("session-common-test") do |workspace|
      stub = File.join(workspace, "claude")
      File.write(stub, "#!/usr/bin/env bash\nprintf 'disable_mouse=%s\\n' \"${CLAUDE_CODE_DISABLE_MOUSE:-}\"\n")
      File.chmod(0o755, stub)

      stdout, stderr, status = run_bash(%(PATH="#{workspace}:$PATH" exec_claude), workspace)

      assert status.success?, stderr
      assert_equal "disable_mouse=1\n", stdout
    end
  end

  private

  def run_bash(script, workspace)
    Open3.capture3("bash", "-c", "source #{SESSION_COMMON}\n#{script}", chdir: workspace)
  end
end
