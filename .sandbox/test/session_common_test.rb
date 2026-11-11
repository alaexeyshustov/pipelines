require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

class SessionCommonTest < Minitest::Test
  SESSION_COMMON = File.expand_path("../profiles/lib/session-common.sh", __dir__)

  def setup
    @workspace = Dir.mktmpdir("session-common-test")
  end

  def teardown
    FileUtils.remove_entry(@workspace)
  end

  def test_dependency_fingerprint_tolerates_missing_files
    File.write(File.join(@workspace, "Gemfile"), "source 'https://rubygems.org'\n")

    stdout, stderr, status = run_bash(<<~'SH')
      fingerprint="$(dependency_fingerprint Gemfile Gemfile.lock .bundle/config)"
      printf 'fingerprint=%s\n' "$fingerprint"
    SH

    assert status.success?, "session aborted under set -e: #{stderr}"
    assert_match(/\Afingerprint=\h{64}\n\z/, stdout)
  end

  def test_dependency_fingerprint_changes_with_file_contents
    gemfile = File.join(@workspace, "Gemfile")
    script = %q(dependency_fingerprint Gemfile .bundle/config)

    File.write(gemfile, "a\n")
    first, = run_bash(script)
    File.write(gemfile, "b\n")
    second, = run_bash(script)

    refute_equal first, second
  end

  def test_exec_claude_leaves_scrolling_and_selection_to_the_host_terminal
    write_stub("claude", "printf 'alt_screen_off=%s disable_mouse=%s\\n' \"${CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN:-}\" \"${CLAUDE_CODE_DISABLE_MOUSE:-}\"\n")

    stdout, stderr, status = run_bash(%(PATH="#{@workspace}:$PATH" exec_claude))

    assert status.success?, stderr
    assert_equal "alt_screen_off=1 disable_mouse=\n", stdout
  end

  def test_configure_github_https_routes_ssh_remotes_through_gh
    write_stub("gh", "printf '%s\\n' \"$*\" >> \"$HOME/gh-calls\"\n")

    _, stderr, status = run_bash(<<~SH)
      export HOME="#{@workspace}" GH_TOKEN=token PATH="#{@workspace}:$PATH"
      configure_github_https
      configure_github_https
    SH

    assert status.success?, stderr
    assert_equal "auth setup-git --hostname github.com\n" * 2, File.read(File.join(@workspace, "gh-calls"))
    assert_equal "https://github.com/owner/repo.git\n", remote_url("git@github.com:owner/repo.git")
  end

  def test_configure_github_https_skips_without_a_token
    _, stderr, status = run_bash(%(export HOME="#{@workspace}"; unset GH_TOKEN; configure_github_https))

    assert status.success?, stderr
    refute File.exist?(File.join(@workspace, ".gitconfig"))
  end

  private

  def run_bash(script)
    Open3.capture3("bash", "-c", "source #{SESSION_COMMON}\n#{script}", chdir: @workspace)
  end

  def write_stub(name, body)
    stub = File.join(@workspace, name)
    File.write(stub, "#!/usr/bin/env bash\n#{body}")
    File.chmod(0o755, stub)
  end

  # The URL git resolves for remote with the workspace as HOME, so the
  # workspace's .gitconfig URL rewrites apply.
  def remote_url(remote)
    url, = Open3.capture2({ "HOME" => @workspace }, "git", "ls-remote", "--get-url", remote, chdir: @workspace)
    url
  end
end
