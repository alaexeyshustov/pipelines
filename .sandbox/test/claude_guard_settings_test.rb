require "minitest/autorun"
require "json"

class ClaudeGuardSettingsTest < Minitest::Test
  LIB = File.expand_path("../profiles/lib/claude", __dir__)
  SETTINGS = File.join(LIB, "managed-settings.json")
  GUARD = File.join(LIB, "hooks/guard-bash")
  PROFILES = %w[claude-matt claude-omcc].freeze

  EXPECTED_DENIES = [
    "Read(**/.env*)",
    "Read(**/credentials.json)",
    "Read(**/*token.yaml)",
    "Read(**/config/*.key)",
    "Read(**/storage/**)"
  ].freeze

  MANAGED_SETTINGS_TARGET = "/etc/claude-code/managed-settings.json".freeze
  GUARD_TARGET = "/usr/local/lib/claude-hooks/guard-bash".freeze

  README = File.join(LIB, "README.md")

  [ "reset --merge", "stash drop", "branch -M", "update-ref -d", "worktree remove --force",
    "checkout -- '*'", "alias.", "${IFS}", "python -c" ].each do |term|
    define_method("test_readme_limits_mentions_#{term.gsub(/\W+/, "_")}") do
      assert_includes limits_section, term
    end
  end

  def test_readme_limits_says_quoted_push_and_gh_mentions_ask
    text = limits_section
    assert_match(/quoted/i, text)
    assert_match(/rg|grep/, text)
    assert_match(/commit message/i, text)
    assert_match(/\bask/, text)
  end

  def limits_section
    File.read(README)[/^## Limits\n(.*?)(?=^## |\z)/m, 1].to_s
  end

  def test_managed_settings_is_valid_json
    assert File.file?(SETTINGS), "missing #{SETTINGS}"
    assert_kind_of Hash, settings
  end

  def test_denies_exactly_the_secret_reads
    assert_equal EXPECTED_DENIES.sort, settings.dig("permissions", "deny").sort
  end

  def test_bash_pre_tool_use_hook_runs_the_guard
    commands = bash_hooks.flat_map { |entry| entry.fetch("hooks").map { |hook| hook["command"] } }

    assert_equal [ GUARD_TARGET ], commands
  end

  def test_managed_settings_has_no_rtk_hook
    refute_match(/rtk/, File.read(SETTINGS))
  end

  def test_guard_script_is_executable
    assert File.executable?(GUARD), "#{GUARD} must be executable"
  end

  PROFILES.each do |profile|
    define_method("test_#{profile}_containerfile_copies_the_settings_and_the_guard") do
      containerfile = File.read(File.expand_path("../profiles/#{profile}/Containerfile", __dir__))

      assert_match(%r{^COPY\s+--from=lib\s+claude/managed-settings\.json\s+#{Regexp.escape(MANAGED_SETTINGS_TARGET)}\s*$}, containerfile)
      assert_match(%r{^COPY\s+--from=lib\s+claude/hooks/guard-bash\s+#{Regexp.escape(GUARD_TARGET)}\s*$|^COPY\s+(?=.*--from=lib)(?=.*--chmod=0?7[5-7][5-7]).*claude/hooks/guard-bash\s+#{Regexp.escape(GUARD_TARGET)}\s*$}, containerfile)
    end

    define_method("test_#{profile}_containerfile_installs_the_guard_executable") do
      containerfile = File.read(File.expand_path("../profiles/#{profile}/Containerfile", __dir__))
      target = Regexp.escape(GUARD_TARGET)
      chmod_flag = %r{^COPY\s+(?=.*--from=lib)(?=.*--chmod=0?7[5-7][5-7]\b).*claude/hooks/guard-bash\s+#{target}\s*$}
      chmod_run = %r{^RUN\s.*chmod\s+(\+x|0?7[5-7][5-7]|a\+x|u\+x)\s+#{target}}

      assert(containerfile.match?(chmod_flag) || containerfile.match?(chmod_run),
        "#{profile} Containerfile must COPY --chmod=0755 or chmod +x #{GUARD_TARGET}")
    end
  end

  DOCUMENTED_LIMITS = ["| sh", "| bash", "bash <<<", "bash <(", "find -exec"].freeze

  DOCUMENTED_LIMITS.each do |limit|
    define_method("test_readme_limits_mentions_#{limit.gsub(/\W+/, "_")}") do
      readme = File.read(File.join(LIB, "README.md"))
      limits = readme[/^## Limits\b.*?(?=^## |\z)/m]

      refute_nil limits, "README has no Limits section"
      assert_includes limits, limit, "README Limits section must mention #{limit.inspect}"
    end
  end

  private

  def settings
    @settings ||= JSON.parse(File.read(SETTINGS))
  end

  def bash_hooks
    entries = settings.dig("hooks", "PreToolUse") || []
    entries.select { |entry| entry["matcher"] == "Bash" }
  end
end
