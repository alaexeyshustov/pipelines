require "minitest/autorun"
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "sandbox_fixtures"

# The helper does not exist until it is implemented. Record the load failure
# and fail each helper-dependent test with it, instead of aborting the file.
begin
  require_relative "../bin/sandbox_network"
rescue LoadError => error
  HELPER_LOAD_ERROR = error
end

SANDBOX_DIR = File.expand_path("..", __dir__)
GATEWAY_DIR = File.join(SANDBOX_DIR, "gateway")
STUB_BIN = File.expand_path("support", __dir__)

# Contract the helper (.sandbox/bin/sandbox_network.rb) must satisfy. Pure
# functions live in `module SandboxNetwork`; inputs are the parsed JSON that
# podman prints (string keys) so no podman is needed for them:
#
#   SandboxNetwork::Error                          raised by every refusal
#   ruleset(interface)                             nft ruleset String
#   gateway_address(network)                       "10.89.7.2" for subnets[0].gateway 10.89.7.1
#   validate_network!(network)                     `network inspect` Hash: not internal, no DNS,
#                                                  options.metric == "200", sandbox label, and no
#                                                  other container on the gateway address
#   validate_gateway_owner!(container)             `container inspect` Hash: needs the egress label
#   validate_container_name!(name)                 agent container names for run-agent
#   active_connection_uri(connections, env)        CONTAINER_HOST > CONTAINER_CONNECTION > default
#   validate_firewall_target!(machines:, connection_uri:, host_os:)
#   validate_ca!(ca_dir)                           ca-cert.pem + ca-key.pem
#   read_pat!(path)                                returns the token
#   agent_args(gateway_ip:, ca_cert:)              Array of `podman run` arguments
#   agent_fingerprint(gateway_ip:, ca_cert:)       sha256 hex
#   gateway_fingerprint(sandbox_dir:, ca_cert:)    sha256 hex over helper + gateway/ + CA cert
#   prepare_state_dir(dir)                         creates it 0700, refuses a wider one
#   proxy_token(dir)                               hex password in dir/proxy-token (0600), stable
#   snapshot_policy(dir, source)                   atomic copy to dir/policy.json, returns its path
module HelperRequired
  def setup
    flunk "sandbox_network.rb is not implemented yet: #{HELPER_LOAD_ERROR.message}" if defined?(HELPER_LOAD_ERROR)
    super
  end
end

class GatewaySourceTest < Minitest::Test
  EXPECTED_DOMAINS = %w[
    rubygems.org index.rubygems.org registry.npmjs.org api.anthropic.com api.openai.com api.mistral.ai
    gmail.googleapis.com www.googleapis.com oauth2.googleapis.com cdn.playwright.dev
    playwright.download.prss.microsoft.com deb.debian.org github.com api.github.com
    *.actions.githubusercontent.com *.blob.core.windows.net storage.googleapis.com
  ].freeze
  GITHUB_REPOSITORIES = %w[alaexeyshustov/pipelines ruby/gem_rbs_collection rubysec/ruby-advisory-db].freeze

  def test_policy_is_a_named_profile_with_valid_json
    assert_equal "pipelines-sandbox-egress", policy.dig("meta", "name")
  end

  def test_policy_allows_exactly_the_documented_domains
    assert_equal EXPECTED_DOMAINS.sort, entries.map { domain_of(_1) }.sort
  end

  def test_gem_registries_allow_only_get_and_head
    %w[rubygems.org index.rubygems.org].each do |domain|
      rules = endpoints(domain)
      refute_empty rules, "#{domain} needs endpoint rules"
      assert_equal [ %w[GET HEAD] ], [ rules.map { _1.fetch("method") }.uniq.sort & %w[GET HEAD] ]
      assert_empty rules.map { _1.fetch("method") } - %w[GET HEAD], "#{domain} must not allow writes"
    end
  end

  # cdn.playwright.dev redirects Chrome for Testing there; the rest of the
  # host (any bucket, uploads) stays closed.
  def test_google_storage_allows_only_reads_of_chrome_for_testing
    rules = endpoints("storage.googleapis.com")

    assert_equal %w[GET HEAD], rules.map { _1.fetch("method") }.uniq.sort
    assert(rules.all? { _1.fetch("path").start_with?("/chrome-for-testing-public/") })
  end

  # nono refuses any intercepted path with an encoded slash, and pnpm fetches
  # every scoped package as /@scope%2Fname, so npm is tunnelled, not filtered.
  def test_npm_registry_is_a_plain_tunnelled_host
    assert_includes entries, "registry.npmjs.org"
  end

  def test_no_path_uses_brace_expansion
    paths = entries.grep(Hash).flat_map { |entry| entry.fetch("endpoints").map { _1.fetch("path") } }

    refute_empty paths
    assert_empty paths.grep(/[{}]/)
  end

  def test_github_git_paths_cover_each_repository_bare_and_recursive
    expected = GITHUB_REPOSITORIES.flat_map { |repo| [ "/#{repo}", "/#{repo}/**", "/#{repo}.git", "/#{repo}.git/**" ] }

    assert_equal expected.sort, endpoints("github.com").map { _1.fetch("path") }.uniq.sort
  end

  def test_github_api_is_limited_to_this_repository_and_graphql
    repo = "alaexeyshustov/pipelines"

    assert_equal [ "/graphql", "/repos/#{repo}", "/repos/#{repo}/**" ], endpoints("api.github.com").map { _1.fetch("path") }.uniq.sort
  end

  def test_policy_passes_nono_validation
    skip_unless_nono_0_82
    stdout, stderr, status = Open3.capture3("nono", "profile", "validate", policy_path)

    assert status.success?, stdout + stderr
  end

  def test_policy_allows_the_issue_examples_under_nono
    skip_unless_nono_0_82
    %w[
      https://github.com/alaexeyshustov/pipelines
      https://github.com/alaexeyshustov/pipelines.git/info/refs
      https://api.github.com/repos/alaexeyshustov/pipelines/issues/1
      https://api.github.com/graphql
      https://x.actions.githubusercontent.com
      https://storage.googleapis.com/chrome-for-testing-public/159.0.8154.6/linux64/chrome-linux64.zip
    ].each { |url| assert_equal "allowed", nono_decision(url), url }
  end

  def test_policy_denies_other_repositories_and_hosts_under_nono
    skip_unless_nono_0_82
    %w[
      https://github.com/openai/codex
      https://api.github.com/repos/other/repo
      https://example.com
    ].each { |url| assert_equal "denied", nono_decision(url), url }
  end

  def test_containerfile_pins_nono_and_verifies_checksums
    containerfile = read_gateway("Containerfile")

    assert_match(/^ARG NONO_VERSION=0\.82\.0$/, containerfile)
    assert_match(/^ARG NONO_SHA256_ARM64=\h{64}$/, containerfile)
    assert_match(/^ARG NONO_SHA256_AMD64=\h{64}$/, containerfile)
    assert_includes containerfile, "sha256sum --check"
    refute_includes containerfile, "SHA256SUMS.txt"
    assert_match(/\bsocat\b/, containerfile)
  end

  def test_entrypoint_runs_nono_proxy_verbosely_with_the_mounted_credentials
    entrypoint = read_gateway("entrypoint.sh")

    assert_includes entrypoint, "nono proxy -v"
    refute_includes entrypoint, "--silent"
    refute_includes entrypoint, "--pass"
    assert_includes entrypoint, "--port 3128"
    assert_includes entrypoint, "--listen 0.0.0.0"
    assert_includes entrypoint, "NONO_PROXY_PASS"
    assert_includes entrypoint, "/run/gateway/token"
    assert_includes entrypoint, "--profile /run/gateway/policy.json"
    assert_includes entrypoint, "--proxy-ca-cert /run/ca/ca-cert.pem"
    assert_includes entrypoint, "--proxy-ca-key /run/ca/ca-key.pem"
  end

  def test_entrypoint_keeps_every_writable_path_under_tmp
    entrypoint = read_gateway("entrypoint.sh")

    %w[HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR].each do |variable|
      assert_match(%r{#{variable}=["']?/tmp\b}, entrypoint, "#{variable} must live under /tmp (read-only root filesystem)")
    end
  end

  def test_entrypoint_relays_ollama_and_supervises_both_children
    entrypoint = read_gateway("entrypoint.sh")

    assert_match(%r{socat TCP-LISTEN:11434,\S*\s+TCP:host\.containers\.internal:11434}, entrypoint)
    assert_includes entrypoint, "wait -n"
  end

  def test_entrypoint_is_valid_bash
    read_gateway("entrypoint.sh")
    _, stderr, status = Open3.capture3("bash", "-n", File.join(GATEWAY_DIR, "entrypoint.sh"))

    assert status.success?, stderr
  end

  private

  def policy_path = File.join(GATEWAY_DIR, "policy.json")

  def read_gateway(name)
    path = File.join(GATEWAY_DIR, name)
    flunk "#{path} does not exist yet" unless File.exist?(path)
    File.read(path)
  end

  def policy = JSON.parse(read_gateway("policy.json"))
  def entries = policy.dig("network", "allow_domain")
  def domain_of(entry) = entry.is_a?(Hash) ? entry.fetch("domain") : entry

  def endpoints(domain)
    entry = entries.find { domain_of(_1) == domain }
    flunk "#{domain} is not in the policy" unless entry.is_a?(Hash)
    entry.fetch("endpoints")
  end

  def skip_unless_nono_0_82
    version, = Open3.capture2e("nono", "--version")
    skip "nono 0.82.x is not installed" unless version.match?(/\b0\.82\.\d+/)
    read_gateway("policy.json")
  rescue Errno::ENOENT
    skip "nono is not installed"
  end

  def nono_decision(url)
    stdout, = Open3.capture3("nono", "why", "--profile", policy_path, "--host", url, "--json")
    JSON.parse(stdout).fetch("status")
  end
end

class SandboxNetworkUnitTest < Minitest::Test
  include HelperRequired

  def setup
    super
    @workspace = Dir.mktmpdir("sandbox-network-test")
  end

  def teardown
    FileUtils.remove_entry(@workspace) if @workspace
  end

  # ruleset

  def test_ruleset_has_the_prelude_and_both_chains_at_priority_minus_20
    rules = SandboxNetwork.ruleset("podman7")

    assert_includes rules, "add table inet pipelines_sandbox"
    assert_includes rules, "flush table inet pipelines_sandbox"
    assert_match(/chain input\s*\{\s*type filter hook input priority -20;/, rules)
    assert_match(/chain forward\s*\{\s*type filter hook forward priority -20;/, rules)
  end

  def test_ruleset_accepts_established_replies_before_dropping_in_each_chain
    rules = SandboxNetwork.ruleset("podman7")
    input = rules[/chain input.*?(?=chain forward)/m]
    forward = rules[/chain forward.*/m]
    accept = 'iifname "podman7" ct state established,related accept'
    drop = 'iifname "podman7" drop'

    [ input, forward ].each do |chain|
      assert_includes chain, accept
      assert_includes chain, drop
      assert_operator chain.index(accept), :<, chain.index(drop)
    end
  end

  def test_ruleset_rejects_an_interface_name_that_could_inject_rules
    assert_raises(SandboxNetwork::Error) { SandboxNetwork.ruleset('podman0"; flush ruleset') }
  end

  # network

  def test_gateway_address_is_the_bridge_gateway_plus_one
    assert_equal "10.89.7.2", SandboxNetwork.gateway_address(network)
  end

  def test_gateway_address_needs_an_ipv4_subnet
    assert_raises(SandboxNetwork::Error) { SandboxNetwork.gateway_address(network("subnets" => [ { "subnet" => "fd00::/64", "gateway" => "fd00::1" } ])) }
    assert_raises(SandboxNetwork::Error) { SandboxNetwork.gateway_address(network("subnets" => [])) }
    assert_raises(SandboxNetwork::Error) { SandboxNetwork.gateway_address(network.tap { _1.delete("subnets") }) }
  end

  def test_validate_network_accepts_the_managed_network
    SandboxNetwork.validate_network!(network)
  end

  def test_validate_network_refuses_unsafe_or_unmanaged_networks
    {
      "internal" => network("internal" => true),
      "DNS-enabled" => network("dns_enabled" => true),
      "wrong metric" => network("options" => { "metric" => "100" }),
      "missing options" => network.tap { _1.delete("options") },
      "missing label" => network.tap { _1.delete("labels") },
      "wrong label" => network("labels" => { "io.pipelines.sandbox.network" => "other" })
    }.each do |description, candidate|
      assert_raises(SandboxNetwork::Error, description) { SandboxNetwork.validate_network!(candidate) }
    end
  end

  def test_validate_network_refuses_another_container_on_the_gateway_address
    squatter = { "abc" => { "name" => "pipelines-claude-matt-x", "interfaces" => { "eth0" => { "subnets" => [ { "ipnet" => "10.89.7.2/24", "gateway" => "10.89.7.1" } ] } } } }
    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_network!(network("containers" => squatter)) }

    assert_includes error.message, "10.89.7.2"
  end

  def test_validate_network_allows_the_gateway_itself_on_its_address
    holder = { "abc" => { "name" => "pipelines-sandbox-gateway", "interfaces" => { "eth0" => { "subnets" => [ { "ipnet" => "10.89.7.2/24", "gateway" => "10.89.7.1" } ] } } } }

    SandboxNetwork.validate_network!(network("containers" => holder))
  end

  # gateway ownership and names

  def test_validate_gateway_owner_refuses_an_unlabelled_container
    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_gateway_owner!("Config" => { "Labels" => {} }) }

    assert_includes error.message, "pipelines-sandbox-gateway"
    assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_gateway_owner!("Config" => {}) }
  end

  def test_validate_gateway_owner_accepts_the_labelled_container
    SandboxNetwork.validate_gateway_owner!("Config" => { "Labels" => { "io.pipelines.sandbox.egress" => "gateway" } })
  end

  def test_container_names
    SandboxNetwork.validate_container_name!("pipelines-claude-matt-gh-267-egress-gateway")

    %w[pipelines-sandbox-gateway pipelines-sandbox-x other-name].each do |name|
      assert_raises(SandboxNetwork::Error, name) { SandboxNetwork.validate_container_name!(name) }
    end
  end

  # firewall target

  def test_firewall_target_accepts_root_on_loopback_with_the_machine_port
    %w[127.0.0.1 localhost].each do |host|
      SandboxNetwork.validate_firewall_target!(machines: [ machine ], connection_uri: "ssh://root@#{host}:54321/run/podman/podman.sock", host_os: "darwin25")
    end
  end

  def test_firewall_target_refuses_what_is_not_the_local_rootful_machine
    {
      "non-root user" => { machines: [ machine ], connection_uri: "ssh://core@127.0.0.1:54321/run/podman/podman.sock" },
      "port mismatch" => { machines: [ machine ], connection_uri: "ssh://root@127.0.0.1:2222/run/podman/podman.sock" },
      "remote host" => { machines: [ machine ], connection_uri: "ssh://root@build.example.com:54321/run/podman/podman.sock" },
      "two machines" => { machines: [ machine, machine("Name" => "other", "Port" => 2222) ], connection_uri: "ssh://root@127.0.0.1:54321/run/podman/podman.sock" },
      "no machine" => { machines: [], connection_uri: "ssh://root@127.0.0.1:54321/run/podman/podman.sock" },
      "rootless machine" => { machines: [ machine("Rootful" => false) ], connection_uri: "ssh://root@127.0.0.1:54321/run/podman/podman.sock" }
    }.each do |description, arguments|
      assert_raises(SandboxNetwork::Error, description) do
        SandboxNetwork.validate_firewall_target!(host_os: "darwin25", **arguments)
      end
    end
  end

  def test_firewall_target_refuses_a_non_macos_host
    assert_raises(SandboxNetwork::Error) do
      SandboxNetwork.validate_firewall_target!(machines: [ machine ], connection_uri: "ssh://root@127.0.0.1:54321/x", host_os: "linux-gnu")
    end
  end

  def test_active_connection_prefers_container_host_then_connection_then_default
    connections = [
      { "Name" => "default-root", "URI" => "ssh://root@127.0.0.1:1/a", "Default" => true },
      { "Name" => "named", "URI" => "ssh://root@127.0.0.1:2/b", "Default" => false }
    ]

    assert_equal "ssh://root@127.0.0.1:1/a", SandboxNetwork.active_connection_uri(connections, {})
    assert_equal "ssh://root@127.0.0.1:2/b", SandboxNetwork.active_connection_uri(connections, { "CONTAINER_CONNECTION" => "named" })
    assert_equal "ssh://root@127.0.0.1:3/c", SandboxNetwork.active_connection_uri(connections, { "CONTAINER_CONNECTION" => "named", "CONTAINER_HOST" => "ssh://root@127.0.0.1:3/c" })
  end

  def test_active_connection_refuses_when_no_connection_is_active
    connections = [ { "Name" => "other", "URI" => "ssh://root@127.0.0.1:1/a", "Default" => false } ]

    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.active_connection_uri(connections, {}) }
    assert_match(/No active Podman connection/, error.message)

    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.active_connection_uri(connections, { "CONTAINER_CONNECTION" => "missing" }) }
    assert_includes error.message, "named missing"
  end

  def test_firewall_target_refuses_an_unparsable_connection_uri
    error = assert_raises(SandboxNetwork::Error) do
      SandboxNetwork.validate_firewall_target!(machines: [ machine ], connection_uri: "ssh://root@127.0.0.1:54321/a b", host_os: "darwin25")
    end

    assert_match(/Unparsable/, error.message)
  end

  def test_gateway_address_refuses_an_unusable_subnet
    [
      [ { "subnet" => "not-a-subnet", "gateway" => "not-an-ip" } ],
      [ { "subnet" => "10.89.7.0/24" } ],
      [ { "subnet" => "10.90.0.0/24", "gateway" => "10.89.7.1" } ]
    ].each do |subnets|
      error = assert_raises(SandboxNetwork::Error, subnets.inspect) { SandboxNetwork.gateway_address(network("subnets" => subnets)) }
      assert_includes error.message, "pipelines-sandbox-net"
    end
  end

  def test_validate_ca_refuses_a_certificate_without_basic_constraints
    ca_dir = File.join(@workspace, "bare")
    FileUtils.mkdir_p(ca_dir)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=bare")
    certificate.public_key = key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600
    certificate.sign(key, OpenSSL::Digest.new("SHA256"))
    File.write(File.join(ca_dir, "ca-cert.pem"), certificate.to_pem)
    SandboxFixtures.write_secret(File.join(ca_dir, "ca-key.pem"), key.private_to_pem)

    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
    assert_includes error.message, "CA:TRUE"
  end

  def test_validate_ca_wraps_an_unreadable_certificate
    ca_dir = write_ca
    File.write(File.join(ca_dir, "ca-cert.pem"), "not a certificate\n")

    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
    assert_includes error.message, "Unreadable CA"
  end

  def test_validate_ca_refuses_a_world_readable_key_even_with_a_valid_pair
    ca_dir = write_ca
    File.chmod(0o640, File.join(ca_dir, "ca-key.pem"))

    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
    assert_includes error.message, "chmod 600"
  end

  def test_atomic_write_leaves_no_temporary_file_when_it_fails
    target = File.join(@workspace, "missing-dir", "file")

    assert_raises(SystemCallError) { SandboxNetwork.atomic_write(target, "x", 0o600) }
    assert_empty Dir.children(@workspace)
  end

  def test_snapshot_policy_replaces_a_stale_copy_and_keeps_it_readable_by_the_gateway
    dir = File.join(@workspace, "state")
    SandboxNetwork.prepare_state_dir(dir)
    source = File.join(@workspace, "policy.json")
    File.write(source, "one")
    SandboxNetwork.snapshot_policy(dir, source)
    File.write(source, "two")
    SandboxNetwork.snapshot_policy(dir, source)

    assert_equal "two", File.read(File.join(dir, "policy.json"))
    assert_equal 0o644, File.stat(File.join(dir, "policy.json")).mode & 0o777
  end

  def test_proxy_token_keeps_an_existing_value
    dir = File.join(@workspace, "state")
    SandboxNetwork.prepare_state_dir(dir)
    File.write(File.join(dir, "proxy-token"), "fixed\n")

    assert_equal "fixed", SandboxNetwork.proxy_token(dir)
  end

  # CA

  def test_validate_ca_accepts_the_fixture
    SandboxNetwork.validate_ca!(write_ca)
  end

  def test_validate_ca_explains_how_to_create_a_missing_ca
    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(File.join(@workspace, "missing")) }

    assert_includes error.message, "openssl genpkey"
    assert_includes error.message, "basicConstraints=critical,CA:TRUE"
  end

  def test_validate_ca_refuses_a_key_that_others_can_read
    ca_dir = write_ca
    File.chmod(0o644, File.join(ca_dir, "ca-key.pem"))

    assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
  end

  def test_validate_ca_refuses_a_sec1_key
    ca_dir = write_ca
    key, certificate = SandboxFixtures.generate_ca
    File.write(File.join(ca_dir, "ca-cert.pem"), certificate.to_pem)
    SandboxFixtures.write_secret(File.join(ca_dir, "ca-key.pem"), key.to_pem)
    assert_includes File.read(File.join(ca_dir, "ca-key.pem")), "BEGIN EC PRIVATE KEY"

    assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
  end

  def test_validate_ca_refuses_a_certificate_that_does_not_match_the_key
    ca_dir = write_ca
    _, other_certificate = SandboxFixtures.generate_ca
    File.write(File.join(ca_dir, "ca-cert.pem"), other_certificate.to_pem)

    assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
  end

  def test_validate_ca_refuses_a_certificate_that_is_not_a_ca
    ca_dir = File.join(@workspace, "leaf")
    FileUtils.mkdir_p(ca_dir)
    key, certificate = SandboxFixtures.generate_ca(ca: false)
    File.write(File.join(ca_dir, "ca-cert.pem"), certificate.to_pem)
    SandboxFixtures.write_secret(File.join(ca_dir, "ca-key.pem"), key.private_to_pem)

    assert_raises(SandboxNetwork::Error) { SandboxNetwork.validate_ca!(ca_dir) }
  end

  # GitHub token

  def test_read_pat_accepts_a_fine_grained_token
    assert_equal "github_pat_test", SandboxNetwork.read_pat!(write_token("github_pat_test\n"))
  end

  def test_read_pat_refuses_classic_and_oauth_tokens_and_says_why
    %w[gho_abc ghp_abc].each do |token|
      error = assert_raises(SandboxNetwork::Error, token) { SandboxNetwork.read_pat!(write_token("#{token}\n")) }
      assert_includes error.message, "/graphql"
    end
  end

  def test_read_pat_refuses_a_token_that_others_can_read
    path = write_token("github_pat_test\n")
    File.chmod(0o644, path)

    assert_raises(SandboxNetwork::Error) { SandboxNetwork.read_pat!(path) }
  end

  def test_read_pat_explains_how_to_create_a_missing_token
    error = assert_raises(SandboxNetwork::Error) { SandboxNetwork.read_pat!(File.join(@workspace, "gh-token")) }

    assert_includes error.message, "gh-token"
    assert_includes error.message, "github_pat_"
  end

  # agent arguments and fingerprints

  def test_agent_args_carry_the_network_hardening_and_proxy_environment
    joined = agent_args.join(" ")

    [
      "--network pipelines-sandbox-net", "--dns=none", "--add-host sandbox-gateway:10.89.7.2", "--restart=no",
      "--http-proxy=false", "--cap-drop NET_ADMIN", "--cap-drop NET_RAW", "--security-opt no-new-privileges",
      "--label io.pipelines.sandbox.egress=gateway",
      *%w[HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy GH_TOKEN].map { "--env #{_1}" },
      "--env NO_PROXY=localhost,127.0.0.1,::1,sandbox-gateway,sandbox-gateway.internal", "--env no_proxy=localhost,127.0.0.1,::1,sandbox-gateway,sandbox-gateway.internal",
      "--env OLLAMA_API_BASE=http://sandbox-gateway.internal:11434/v1", "--add-host sandbox-gateway.internal:10.89.7.2"
    ].each { assert_includes joined, _1 }
  end

  def test_agent_args_mount_only_the_ca_certificate_and_never_a_secret
    joined = agent_args.join(" ")

    assert_includes joined, "dst=/run/sandbox-ca.crt,ro"
    assert_includes joined, "src=#{@last_ca_dir}/ca-cert.pem"
    refute_includes joined, "ca-key.pem"
    refute_includes joined, "proxy-token"
    refute_includes joined, "github_pat_"
    refute_match(/nono:/, joined)
  end

  def test_agent_fingerprint_follows_the_ca_and_the_gateway_address_only
    ca_dir = write_ca
    cert = File.join(ca_dir, "ca-cert.pem")
    first = SandboxNetwork.agent_fingerprint(gateway_ip: "10.89.7.2", ca_cert: cert)
    assert_match(/\A\h{64}\z/, first)
    assert_equal first, SandboxNetwork.agent_fingerprint(gateway_ip: "10.89.7.2", ca_cert: cert)
    refute_equal first, SandboxNetwork.agent_fingerprint(gateway_ip: "10.89.8.2", ca_cert: cert)

    File.write(cert, SandboxFixtures.generate_ca.last.to_pem)
    refute_equal first, SandboxNetwork.agent_fingerprint(gateway_ip: "10.89.7.2", ca_cert: cert)

    assert_equal %i[ca_cert gateway_ip], SandboxNetwork.method(:agent_fingerprint).parameters.map(&:last).sort
  end

  def test_gateway_fingerprint_follows_the_helper_the_gateway_files_the_policy_and_the_ca
    sandbox_dir = File.join(@workspace, "sandbox")
    cert = File.join(write_ca, "ca-cert.pem")
    {
      "bin/sandbox-network" => "#!/bin/bash\n", "bin/sandbox_network.rb" => "# helper\n",
      "gateway/Containerfile" => "FROM scratch\n", "gateway/entrypoint.sh" => "#!/bin/bash\n",
      "gateway/policy.json" => "{}\n"
    }.each do |relative, contents|
      FileUtils.mkdir_p(File.dirname(File.join(sandbox_dir, relative)))
      File.write(File.join(sandbox_dir, relative), contents)
    end
    baseline = SandboxNetwork.gateway_fingerprint(sandbox_dir: sandbox_dir, ca_cert: cert)
    assert_match(/\A\h{64}\z/, baseline)

    %w[bin/sandbox_network.rb bin/sandbox-network gateway/Containerfile gateway/entrypoint.sh gateway/policy.json].each do |relative|
      path = File.join(sandbox_dir, relative)
      original = File.read(path)
      File.write(path, "#{original}# changed\n")
      refute_equal baseline, SandboxNetwork.gateway_fingerprint(sandbox_dir: sandbox_dir, ca_cert: cert), relative
      File.write(path, original)
    end

    assert_equal baseline, SandboxNetwork.gateway_fingerprint(sandbox_dir: sandbox_dir, ca_cert: cert)
    File.write(cert, SandboxFixtures.generate_ca.last.to_pem)
    refute_equal baseline, SandboxNetwork.gateway_fingerprint(sandbox_dir: sandbox_dir, ca_cert: cert)
  end

  # state directory

  def test_prepare_state_dir_creates_a_private_directory
    dir = File.join(@workspace, "state")
    SandboxNetwork.prepare_state_dir(dir)

    assert_equal 0o700, File.stat(dir).mode & 0o777
  end

  def test_prepare_state_dir_refuses_a_wider_directory
    dir = File.join(@workspace, "state")
    FileUtils.mkdir_p(dir)
    File.chmod(0o755, dir)

    assert_raises(SandboxNetwork::Error) { SandboxNetwork.prepare_state_dir(dir) }
  end

  def test_proxy_token_is_generated_once_with_mode_600
    dir = File.join(@workspace, "state")
    SandboxNetwork.prepare_state_dir(dir)
    token = SandboxNetwork.proxy_token(dir)

    assert_match(/\A\h{64}\z/, token)
    assert_equal token, SandboxNetwork.proxy_token(dir)
    assert_equal token, File.read(File.join(dir, "proxy-token")).strip
    assert_equal 0o600, File.stat(File.join(dir, "proxy-token")).mode & 0o777
  end

  def test_snapshot_policy_copies_the_source_atomically
    dir = File.join(@workspace, "state")
    SandboxNetwork.prepare_state_dir(dir)
    source = File.join(@workspace, "policy.json")
    File.write(source, %({"meta":{"name":"x"}}\n))

    snapshot = SandboxNetwork.snapshot_policy(dir, source)

    assert_equal File.join(dir, "policy.json"), snapshot
    assert_equal File.read(source), File.read(snapshot)
    assert_equal [ "policy.json" ], Dir.children(dir)
  end

  private

  def network(overrides = {})
    {
      "name" => "pipelines-sandbox-net", "network_interface" => "podman7", "internal" => false, "dns_enabled" => false,
      "subnets" => [ { "subnet" => "10.89.7.0/24", "gateway" => "10.89.7.1" } ],
      "labels" => { "io.pipelines.sandbox.network" => "shared" }, "options" => { "metric" => "200" }, "containers" => {}
    }.merge(overrides)
  end

  def machine(overrides = {})
    { "Name" => "podman-machine-default", "Rootful" => true, "Port" => 54_321 }.merge(overrides)
  end

  def write_ca
    ca_dir = File.join(@workspace, "ca-#{rand(1_000_000)}")
    FileUtils.mkdir_p(ca_dir)
    SandboxFixtures.write_ca(ca_dir)
    @last_ca_dir = ca_dir
  end

  def write_token(contents)
    path = File.join(@workspace, "gh-token")
    SandboxFixtures.write_secret(path, contents)
    path
  end

  def agent_args
    SandboxNetwork.agent_args(gateway_ip: "10.89.7.2", ca_cert: File.join(@last_ca_dir || write_ca, "ca-cert.pem"))
  end
end

class SandboxNetworkCliTest < Minitest::Test
  include HelperRequired

  HELPER = File.join(SANDBOX_DIR, "bin", "sandbox-network")
  GATEWAY = "pipelines-sandbox-gateway".freeze
  AGENT = "pipelines-claude-matt-gh-267".freeze

  def setup
    super
    @workspace = Dir.mktmpdir("sandbox-network-cli")
    @home = File.join(@workspace, "home")
    @state = SandboxFixtures.install(@home)
    @podman_state = File.join(@workspace, "podman-state")
    @log = File.join(@workspace, "podman.log")
    @nft_log = File.join(@workspace, "nft.log")
    @env_log = File.join(@workspace, "podman-env.log")
  end

  def teardown
    FileUtils.remove_entry(@workspace) if @workspace
  end

  def test_ensure_on_a_healthy_gateway_only_reconciles_the_firewall
    _, stderr, status = run_cli("ensure")

    assert status.success?, stderr
    assert_empty(calls.grep(/\A(?:container )?(?:rm|run|build|start)\b/))
    assert_equal SandboxNetwork.ruleset("podman7"), File.read(@nft_log)
  end

  def test_ensure_creates_the_state_directory_assets
    _, stderr, status = run_cli("ensure")

    assert status.success?, stderr
    assert_match(/\A\h{64}\n?\z/, File.read(File.join(@state, "proxy-token")))
    assert_equal File.read(File.join(SANDBOX_DIR, "gateway", "policy.json")), File.read(File.join(@state, "policy.json"))
  end

  def test_ensure_builds_and_starts_an_absent_gateway
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY" => "absent", "STUB_PODMAN_IMAGE_MISSING" => "true")
    run = calls.find { _1.match?(/\Arun --detach\b/) }
    fingerprint = gateway_fingerprint

    assert status.success?, stderr
    assert run, "expected podman run --detach, got #{calls}"
    assert_operator calls.index { _1.start_with?("network ") }, :<, calls.index { _1.start_with?("build ") }
    assert_operator calls.index { _1.start_with?("build ") }, :<, calls.index(run)
    [
      "--name #{GATEWAY}", "--read-only", "--cap-drop ALL", "--security-opt no-new-privileges",
      "--sysctl net.ipv4.ip_forward=0", "--network pipelines-sandbox-net:ip=10.89.7.2", "--http-proxy=false",
      "io.pipelines.sandbox.egress=gateway", "io.pipelines.sandbox.gateway-config=#{fingerprint}",
      "localhost/pipelines-sandbox-gateway:#{fingerprint}"
    ].each { assert_includes run, _1 }
    assert_match(%r{src=\S+/ca/ca-key\.pem,dst=/run/ca/ca-key\.pem,ro}, run)
    assert_match(%r{src=\S+/ca/ca-cert\.pem,dst=/run/ca/ca-cert\.pem,ro}, run)
    assert_match(%r{src=\S+/proxy-token,dst=/run/gateway/token,ro}, run)
    assert_match(%r{src=\S+/policy\.json,dst=/run/gateway/policy\.json,ro}, run)
    refute_includes run, File.read(File.join(@state, "proxy-token")).strip
  end

  def test_ensure_replaces_a_gateway_with_a_stale_fingerprint
    _, stderr, status = run_cli("ensure", "STUB_GATEWAY_FINGERPRINT" => "stale")
    removal = calls.index { _1.match?(/rm --force\b.*#{GATEWAY}/) }
    run = calls.index { _1.match?(/\Arun --detach\b/) }

    assert status.success?, stderr
    assert removal, "expected the stale gateway to be removed, got #{calls}"
    assert run, "expected a new gateway, got #{calls}"
    assert_operator removal, :<, run
  end

  def test_ensure_restarts_an_exited_gateway
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY" => "exited")

    assert status.success?, stderr
    assert(calls.any? { _1.match?(/\A(?:container )?start\b.*#{GATEWAY}/) }, calls.inspect)
    assert_empty(calls.grep(/\A(?:container )?rm\b/))
  end

  def test_ensure_creates_an_absent_network
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_NETWORK" => "absent")

    assert status.success?, stderr
    assert_includes calls, "network create --disable-dns --opt metric=200 --label io.pipelines.sandbox.network=shared pipelines-sandbox-net"
  end

  def test_ensure_refuses_an_unmanaged_gateway_container
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY" => "unmanaged")

    refute status.success?
    assert_includes stderr, GATEWAY
    assert_empty(calls.grep(/\A(?:container )?(?:rm|run)\b/))
  end

  def test_ensure_refuses_an_unlabelled_network
    unlabelled = { "name" => "pipelines-sandbox-net", "network_interface" => "podman7", "internal" => false, "dns_enabled" => false,
                   "subnets" => [ { "subnet" => "10.89.7.0/24", "gateway" => "10.89.7.1" } ], "containers" => {} }
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_NETWORK_JSON" => JSON.generate([ unlabelled ]))

    refute status.success?
    assert_includes stderr, "pipelines-sandbox-net"
    assert_empty(calls.grep(/\A(?:container )?(?:rm|run)\b/))
  end

  def test_ensure_refuses_rootless_podman_before_touching_anything_else
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_ROOTLESS" => "true")

    refute status.success?
    assert_match(/rootless/i, stderr)
    assert_empty(calls.grep(/\A(?:network|machine ssh|build|run|container rm|rm)\b/))
  end

  def test_ensure_refuses_a_remote_engine_that_is_not_the_local_machine
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_CONNECTION_URI" => "ssh://root@127.0.0.1:1/run/podman/podman.sock")

    refute status.success?
    refute_empty stderr
    refute File.exist?(@nft_log)
  end

  def test_ensure_names_the_gateway_logs_when_it_never_becomes_ready
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY_UNREADY" => "true")

    refute status.success?
    assert_includes stderr, "podman logs #{GATEWAY}"
  end

  def test_ensure_names_the_gateway_logs_when_it_stops_while_starting
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY_UNREADY" => "exited")

    refute status.success?
    assert_includes stderr, "podman logs #{GATEWAY}"
  end

  def test_ensure_fails_when_the_firewall_cannot_be_applied
    _, stderr, status = run_cli("ensure", "STUB_FIREWALL_FAILURE" => "true")

    refute status.success?
    refute_empty stderr
  end

  def test_ensure_refuses_a_missing_ca
    FileUtils.rm_rf(File.join(@state, "ca"))
    _, stderr, status = run_cli("ensure")

    refute status.success?
    assert_includes stderr, "openssl genpkey"
    assert_empty(calls.grep(/\A(?:run|build|container rm|rm)\b/))
  end

  def test_fingerprints_are_printed_and_differ
    agent, agent_stderr, agent_status = run_cli("fingerprint")
    gateway, gateway_stderr, gateway_status = run_cli("fingerprint", "--gateway")

    assert agent_status.success?, agent_stderr
    assert gateway_status.success?, gateway_stderr
    assert_match(/\A\h{64}\n\z/, agent)
    assert_match(/\A\h{64}\n\z/, gateway)
    refute_equal agent, gateway
  end

  def test_run_agent_refuses_the_gateways_own_name
    _, stderr, status = run_cli("run-agent", GATEWAY, "--interactive", "image")

    refute status.success?
    refute_empty stderr
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_run_agent_refuses_a_name_outside_the_agent_pattern
    _, _, status = run_cli("run-agent", "other-name", "--interactive", "image")

    refute status.success?
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_run_agent_refuses_a_copy_that_is_not_in_the_primary_checkout
    copy = File.join(@workspace, "copy", ".sandbox", "bin")
    FileUtils.mkdir_p(copy)
    %w[sandbox-network sandbox_network.rb].each { FileUtils.cp(File.join(SANDBOX_DIR, "bin", _1), copy) }

    _, stderr, status = run_cli("run-agent", AGENT, "--interactive", "image", helper: File.join(copy, "sandbox-network"))

    refute status.success?
    assert_match(/primary/i, stderr)
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_run_agent_refuses_a_token_that_is_not_a_fine_grained_pat
    File.write(File.join(@state, "gh-token"), "ghp_classic\n")
    _, stderr, status = run_cli("run-agent", AGENT, "--interactive", "image")

    refute status.success?
    assert_includes stderr, "github_pat_"
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_run_agent_runs_podman_with_the_agent_args_and_the_proxy_environment
    _, stderr, status = run_cli("run-agent", AGENT, "--interactive", "example/image:tag")
    run = calls.find { _1.start_with?("run ") }
    token = File.read(File.join(@state, "proxy-token")).strip
    proxy = "http://nono:#{token}@sandbox-gateway:3128"
    environment = File.read(@env_log).split("\0").to_h { _1.split("=", 2) }

    assert status.success?, stderr
    assert run, "expected podman run, got #{calls}"
    ["--network pipelines-sandbox-net", "--add-host sandbox-gateway:10.89.7.2", "--dns=none", "--cap-drop NET_RAW",
     "--interactive", "--name #{AGENT}", "example/image:tag"].each { assert_includes run, _1 }
    refute_includes run, token
    refute_includes run, "ca-key.pem"
    %w[HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy].each { assert_equal proxy, environment[_1], _1 }
    assert_includes run, "--env NO_PROXY=localhost,127.0.0.1,::1,sandbox-gateway,sandbox-gateway.internal"
    assert_equal "github_pat_test", environment["GH_TOKEN"]
  end

  def test_ensure_connects_a_running_gateway_that_is_off_the_shared_network
    FileUtils.mkdir_p(File.join(@podman_state, "containers"))
    File.write(File.join(@podman_state, "containers", "#{GATEWAY}.json"), JSON.generate(
      "Name" => GATEWAY, "Id" => "abc", "State" => { "Status" => "running" }, "NetworkIPs" => {},
      "Config" => { "Labels" => { "io.pipelines.sandbox.egress" => "gateway", "io.pipelines.sandbox.gateway-config" => gateway_fingerprint } }
    ))
    _, stderr, status = run_cli("ensure")

    assert status.success?, stderr
    assert_includes calls, "network connect --ip 10.89.7.2 pipelines-sandbox-net #{GATEWAY}"
    assert_empty(calls.grep(/\A(?:container )?(?:rm|run|build)\b/))
  end

  def test_ensure_does_not_reconnect_a_gateway_already_on_the_network
    _, stderr, status = run_cli("ensure")

    assert status.success?, stderr
    assert_empty(calls.grep(/\Anetwork connect\b/))
  end

  def test_ensure_reports_a_failed_image_build_and_starts_nothing
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY" => "absent", "STUB_PODMAN_IMAGE_MISSING" => "true", "STUB_PODMAN_BUILD_FAILURE" => "true")

    refute status.success?
    assert_includes stderr, "build of the gateway image failed"
    assert_empty(calls.grep(/\Arun\b/))
    refute File.exist?(@nft_log)
  end

  def test_ensure_skips_the_build_when_the_image_exists
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY" => "absent")

    assert status.success?, stderr
    assert_empty(calls.grep(/\Abuild\b/))
    assert(calls.any? { _1.start_with?("run --detach") }, calls.inspect)
  end

  def test_ensure_refuses_a_bad_token_before_creating_anything
    File.write(File.join(@state, "gh-token"), "ghp_classic\n")
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_GATEWAY" => "absent", "STUB_PODMAN_NETWORK" => "absent")

    refute status.success?
    assert_includes stderr, "github_pat_"
    assert_empty(calls.grep(/\A(?:network create|build|run|machine ssh)\b/))
  end

  def test_ensure_refuses_a_state_directory_others_can_read
    File.chmod(0o755, @state)
    _, stderr, status = run_cli("ensure")

    refute status.success?
    assert_includes stderr, "chmod 700"
    assert_empty(calls.grep(/\A(?:network|machine ssh|build|run|rm)\b/))
  end

  def test_ensure_refuses_an_unsafe_existing_network_before_the_gateway
    network = { "name" => "pipelines-sandbox-net", "network_interface" => "podman7", "internal" => true, "dns_enabled" => false,
                "subnets" => [ { "subnet" => "10.89.7.0/24", "gateway" => "10.89.7.1" } ],
                "labels" => { "io.pipelines.sandbox.network" => "shared" }, "options" => { "metric" => "200" }, "containers" => {} }
    _, stderr, status = run_cli("ensure", "STUB_PODMAN_NETWORK_JSON" => JSON.generate([ network ]))

    refute status.success?
    assert_includes stderr, "internal"
    assert_empty(calls.grep(/\A(?:container )?(?:rm|run|start)\b|machine ssh/))
  end

  def test_ensure_prints_usage_for_unknown_or_malformed_commands
    [ [], [ "bogus" ], [ "ensure", "extra" ], [ "fingerprint", "--bogus" ], [ "fingerprint", "--gateway", "extra" ], [ "run-agent" ] ].each do |arguments|
      _, stderr, status = run_cli(*arguments)

      refute status.success?, arguments.inspect
      assert_includes stderr, "Usage:", arguments.inspect
    end
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_fingerprint_without_a_ca_explains_how_to_create_one
    FileUtils.rm_rf(File.join(@state, "ca"))
    _, stderr, status = run_cli("fingerprint")

    refute status.success?
    assert_includes stderr, "openssl genpkey"
  end

  def test_agent_fingerprint_needs_the_network_to_exist
    _, stderr, status = run_cli("fingerprint", "STUB_PODMAN_NETWORK" => "absent")

    refute status.success?
    assert_includes stderr, "sandbox-network ensure"
  end

  def test_gateway_fingerprint_does_not_need_podman
    agent, = run_cli("fingerprint", "STUB_PODMAN_NETWORK" => "absent")
    gateway, stderr, status = run_cli("fingerprint", "--gateway", "STUB_PODMAN_NETWORK" => "absent")

    assert_empty agent
    assert status.success?, stderr
    assert_match(/\A\h{64}\n\z/, gateway)
  end

  def test_run_agent_passes_the_secrets_only_through_the_environment
    _, stderr, status = run_cli("run-agent", AGENT, "image")
    environment = File.read(@env_log)

    assert status.success?, stderr
    assert_includes environment, "GH_TOKEN=github_pat_test\0"
    run = calls.find { _1.start_with?("run ") }
    refute_includes run, "github_pat_test"
    assert_includes run, "--env GH_TOKEN"
    assert_includes run, "--env HTTP_PROXY"
  end

  def test_run_agent_names_the_container_it_validated
    _, stderr, status = run_cli("run-agent", AGENT, "image")

    assert status.success?, stderr
    assert_match(/\Arun --name #{AGENT} /, calls.find { _1.start_with?("run ") })
  end

  def test_run_agent_refuses_a_caller_supplied_name
    %W[--name --name=other].each do |flag|
      arguments = flag == "--name" ? [flag, "other"] : [flag]
      _, stderr, status = run_cli("run-agent", AGENT, *arguments, "image")

      refute status.success?, flag
      assert_includes stderr, "--name"
    end
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_run_agent_reconciles_the_gateway_and_firewall_before_launching
    _, stderr, status = run_cli("run-agent", AGENT, "image")

    assert status.success?, stderr
    assert_operator calls.index { _1.start_with?("machine ssh") }, :<, calls.index { _1.start_with?("run ") }
  end

  def test_run_agent_does_not_launch_when_the_gateway_is_not_ready
    _, stderr, status = run_cli("run-agent", AGENT, "image", "STUB_PODMAN_GATEWAY_UNREADY" => "exited")

    refute status.success?
    assert_includes stderr, "podman logs #{GATEWAY}"
    assert_empty(calls.grep(/\Arun\b/))
  end

  def test_run_agent_refuses_reserved_sandbox_names
    %w[pipelines-sandbox pipelines-sandbox-gateway pipelines-sandbox-x].each do |name|
      _, _, status = run_cli("run-agent", name, "image")

      refute status.success?, name
    end
    assert_empty(calls.grep(/\Arun\b/))
  end

  private

  def calls
    File.exist?(@log) ? File.readlines(@log, chomp: true) : []
  end

  def cli_environment(extra = {})
    {
      "HOME" => @home,
      "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}",
      "STUB_PODMAN_STATE_DIR" => @podman_state,
      "STUB_PODMAN_LOG" => @log,
      "STUB_PODMAN_NFT_LOG" => @nft_log,
      "STUB_PODMAN_ENV_LOG" => @env_log,
      "STUB_GATEWAY_FINGERPRINT" => gateway_fingerprint
    }.merge(extra)
  end

  def gateway_fingerprint
    @gateway_fingerprint ||= Open3.capture3(
      { "HOME" => @home, "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}", "STUB_PODMAN_STATE_DIR" => @podman_state },
      HELPER, "fingerprint", "--gateway"
    ).first.strip
  end

  # run_cli("ensure", "STUB_X" => "y") -- string keys add environment variables;
  # helper: points at another copy of the wrapper.
  def run_cli(*arguments, **extra)
    helper = extra.delete(:helper) || HELPER
    Open3.capture3(cli_environment(extra), helper, *arguments)
  end
end
