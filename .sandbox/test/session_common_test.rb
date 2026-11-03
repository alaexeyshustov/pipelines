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

  def test_exec_claude_leaves_scrolling_and_selection_to_the_host_terminal
    Dir.mktmpdir("session-common-test") do |workspace|
      stub = File.join(workspace, "claude")
      File.write(stub, "#!/usr/bin/env bash\nprintf 'alt_screen_off=%s disable_mouse=%s\\n' \"${CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN:-}\" \"${CLAUDE_CODE_DISABLE_MOUSE:-}\"\n")
      File.chmod(0o755, stub)

      stdout, stderr, status = run_bash(%(PATH="#{workspace}:$PATH" exec_claude), workspace)

      assert status.success?, stderr
      assert_equal "alt_screen_off=1 disable_mouse=\n", stdout
    end
  end

  def test_configure_github_https_routes_ssh_remotes_through_gh
    Dir.mktmpdir("session-common-test") do |workspace|
      stub = File.join(workspace, "gh")
      File.write(stub, "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$HOME/gh-calls\"\n")
      File.chmod(0o755, stub)

      _, stderr, status = run_bash(<<~SH, workspace)
        export HOME="#{workspace}" GH_TOKEN=token PATH="#{workspace}:$PATH"
        configure_github_https
        configure_github_https
      SH

      assert status.success?, stderr
      assert_equal "auth setup-git --hostname github.com\n" * 2, File.read(File.join(workspace, "gh-calls"))
      rewritten, = Open3.capture2({ "HOME" => workspace }, "git", "ls-remote", "--get-url", "git@github.com:owner/repo.git", chdir: workspace)
      assert_equal "https://github.com/owner/repo.git\n", rewritten
    end
  end

  def test_configure_github_https_skips_without_a_token
    Dir.mktmpdir("session-common-test") do |workspace|
      _, stderr, status = run_bash(%(export HOME="#{workspace}"; unset GH_TOKEN; configure_github_https), workspace)

      assert status.success?, stderr
      refute File.exist?(File.join(workspace, ".gitconfig"))
    end
  end

  private

  def run_bash(script, workspace)
    Open3.capture3("bash", "-c", "source #{SESSION_COMMON}\n#{script}", chdir: workspace)
  end
end
