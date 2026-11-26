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

  def test_configure_sandbox_ca_refuses_without_the_certificate
    environment = ca_environment(cert: File.join(@workspace, "missing.crt"))
    _, stderr, status = run_bash("#{environment}\nconfigure_sandbox_ca")

    assert_equal 1, status.exitstatus
    assert_match(%r{/run/sandbox-ca\.crt|attach-worktree}, stderr)
    assert_empty Dir.children(ca_store)
  end

  def test_configure_sandbox_ca_refuses_without_the_proxy
    environment = ca_environment(proxy: nil)
    _, stderr, status = run_bash("#{environment}\nconfigure_sandbox_ca")

    assert_equal 1, status.exitstatus
    assert_includes stderr, "HTTPS_PROXY"
    assert_empty Dir.children(ca_store)
  end

  def test_configure_sandbox_ca_installs_the_certificate_and_exports_the_trust_environment
    write_stub("update-ca-certificates", %(printf 'called present=%s\\n' "$([[ -f "$SANDBOX_CA_STORE/pipelines-sandbox.crt" ]] && echo yes || echo no)" >> "#{@workspace}/update.log"\n))
    stdout, stderr, status = run_bash(<<~SH)
      #{ca_environment}
      PATH="#{@workspace}:$PATH"
      configure_sandbox_ca
      for variable in SSL_CERT_FILE CURL_CA_BUNDLE REQUESTS_CA_BUNDLE BUNDLE_SSL_CA_CERT GIT_SSL_CAINFO NODE_EXTRA_CA_CERTS NODE_USE_ENV_PROXY CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
        printf '%s=%s\\n' "$variable" "${!variable}"
      done
    SH

    assert status.success?, stderr
    assert_equal File.read(ca_cert), File.read(File.join(ca_store, "pipelines-sandbox.crt"))
    assert_equal "called present=yes\n", File.read(File.join(@workspace, "update.log"))
    bundle = "/etc/ssl/certs/ca-certificates.crt"
    assert_equal <<~EXPECTED, stdout
      SSL_CERT_FILE=#{bundle}
      CURL_CA_BUNDLE=#{bundle}
      REQUESTS_CA_BUNDLE=#{bundle}
      BUNDLE_SSL_CA_CERT=#{bundle}
      GIT_SSL_CAINFO=#{bundle}
      NODE_EXTRA_CA_CERTS=#{ca_cert}
      NODE_USE_ENV_PROXY=1
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
    EXPECTED
  end

  def test_both_claude_sessions_configure_the_sandbox_ca_before_anything_else
    lib_functions = File.read(SESSION_COMMON).scan(/^(\w+)\(\)/).flatten
    refute_empty lib_functions

    Dir[File.expand_path("../profiles/claude-*/claude-session", __dir__)].each do |script|
      source = File.read(script)
      functions = lib_functions + source.scan(/^(\w+)\(\)/).flatten
      calls = source.lines.filter_map { |line| line[/\A(\w+)(?:\s|\z)/, 1] }.select { functions.include?(_1) }

      assert_equal "configure_sandbox_ca", calls.first, "#{File.basename(File.dirname(script))} must call configure_sandbox_ca first (calls: #{calls})"
    end
  end

  private

  def ca_cert = File.join(@workspace, "sandbox-ca.crt")
  def ca_store = File.join(@workspace, "ca-store").tap { FileUtils.mkdir_p(_1) }

  # Shell that points the bootstrap at temporary paths; proxy: nil leaves
  # HTTPS_PROXY unset.
  def ca_environment(cert: ca_cert, proxy: "http://nono:secret@sandbox-gateway:3128")
    File.write(ca_cert, "-----BEGIN CERTIFICATE-----\nstub\n-----END CERTIFICATE-----\n")
    lines = [ "export SANDBOX_CA_CERT=#{cert} SANDBOX_CA_STORE=#{ca_store}" ]
    lines << (proxy ? "export HTTPS_PROXY=#{proxy}" : "unset HTTPS_PROXY https_proxy")
    lines.join("\n")
  end

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
