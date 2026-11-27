#!/usr/bin/env ruby
# frozen_string_literal: true

# Owns the shared egress gateway of the agent sandbox (GH #267): the
# `pipelines-sandbox-net` bridge, the `pipelines-sandbox-gateway` container
# running nono, and the VM firewall that keeps agents on that bridge from
# reaching anything else.
#
#   sandbox-network ensure                         reconcile network, gateway and firewall
#   sandbox-network run-agent NAME PODMAN_ARGS...  ensure, then `podman run` an agent through the gateway
#   sandbox-network fingerprint [--gateway]        print the agent (default) or gateway fingerprint
#
# Pure functions live in SandboxNetwork; the CLI only runs when this file is
# executed. Stdlib only: the helper must work before any bundle exists.

require "digest"
require "fileutils"
require "ipaddr"
require "json"
require "open3"
require "openssl"
require "rbconfig"
require "securerandom"
require "uri"

module SandboxNetwork
  class Error < StandardError; end

  ROOT = File.expand_path("../..", __dir__)
  SANDBOX_DIR = File.join(ROOT, ".sandbox")

  NETWORK = "pipelines-sandbox-net"
  GATEWAY = "pipelines-sandbox-gateway"
  GATEWAY_HOST = "sandbox-gateway"
  EGRESS_LABEL = "io.pipelines.sandbox.egress"
  CONFIG_LABEL = "io.pipelines.sandbox.gateway-config"
  NETWORK_LABEL = "io.pipelines.sandbox.network"
  TABLE = "pipelines_sandbox"
  INTERFACE_PATTERN = /\A[a-zA-Z0-9_.-]{1,15}\z/
  AGENT_NAME_PATTERN = /\Apipelines-[a-z0-9]+(?:-[a-z0-9]+)*\z/
  RESERVED_NAME_PATTERN = /\Apipelines-sandbox(?:-|\z)/
  PROXY_VARIABLES = %w[HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy].freeze
  # Ollama answers 403 to a Host that isn't local; it accepts *.internal, so
  # the relay gets its own alias for the same gateway address.
  OLLAMA_HOST = "sandbox-gateway.internal"
  NO_PROXY = "localhost,127.0.0.1,::1,#{GATEWAY_HOST},#{OLLAMA_HOST}"
  OLLAMA_API_BASE = "http://#{OLLAMA_HOST}:11434/v1"
  READY_SCRIPT = "exec 3<>/dev/tcp/127.0.0.1/3128 && exec 4<>/dev/tcp/127.0.0.1/11434"
  READY_ATTEMPTS = 30
  READY_INTERVAL = 0.2

  module_function

  def state_dir = File.join(Dir.home, ".config", "pipelines-sandbox")

  # Firewall

  # Filters only the labelled bridge, in a table of our own: never flush the
  # VM's or Netavark's rules. Replies to connections made toward the agents
  # (the published app port) pass; anything new from an agent is dropped.
  # With br_netfilter off, agent-to-gateway traffic is L2 and never reaches
  # these hooks, so it is not listed.
  def ruleset(interface)
    raise Error, "Refusing an unexpected bridge interface name: #{interface.inspect}" unless interface.to_s.match?(INTERFACE_PATTERN)

    match = %(iifname "#{interface}")
    <<~NFT
      add table inet #{TABLE}
      flush table inet #{TABLE}
      table inet #{TABLE} {
        chain input { type filter hook input priority -20; policy accept;
          #{match} ct state established,related accept
          #{match} drop
        }
        chain forward { type filter hook forward priority -20; policy accept;
          #{match} ct state established,related accept
          #{match} drop
        }
      }
    NFT
  end

  # CONTAINER_HOST wins over CONTAINER_CONNECTION, which wins over the default.
  def active_connection_uri(connections, env)
    return env["CONTAINER_HOST"] unless env["CONTAINER_HOST"].to_s.empty?

    name = env["CONTAINER_CONNECTION"].to_s
    connection = name.empty? ? connections.find { _1["Default"] } : connections.find { _1["Name"] == name }
    raise Error, "No active Podman connection#{" named #{name}" unless name.empty?}" unless connection

    connection.fetch("URI")
  end

  # The firewall is applied inside the one local rootful `podman machine`, so
  # the engine we talk to must be exactly that VM. Returns the machine's name.
  def validate_firewall_target!(machines:, connection_uri:, host_os:)
    raise Error, "The VM firewall is only supported on macOS with a podman machine (host: #{host_os})" unless host_os.to_s.include?("darwin")
    raise Error, "Expected exactly one podman machine, found #{machines.size}" unless machines.size == 1

    machine = machines.first
    raise Error, "Podman machine #{machine["Name"]} must be rootful (podman machine set --rootful)" unless machine["Rootful"] == true

    uri = begin
      URI.parse(connection_uri.to_s)
    rescue URI::InvalidURIError
      raise Error, "Unparsable Podman connection URI: #{connection_uri}"
    end
    unless uri.scheme == "ssh" && uri.user == "root" && %w[localhost 127.0.0.1].include?(uri.host) && uri.port == machine["Port"]
      raise Error, "The active Podman connection (#{connection_uri}) is not the local rootful machine #{machine["Name"]} (ssh://root@127.0.0.1:#{machine["Port"]})"
    end

    machine.fetch("Name")
  end

  # Network and gateway

  def gateway_address(network)
    subnet = Array(network["subnets"]).first or raise Error, "#{NETWORK} has no subnet"
    gateway = IPAddr.new(subnet.fetch("gateway"))
    raise Error, "#{NETWORK} needs an IPv4 subnet" unless gateway.ipv4? && IPAddr.new(subnet.fetch("subnet")).include?(gateway)

    gateway.succ.to_s
  rescue IPAddr::Error, KeyError
    raise Error, "#{NETWORK} has an unusable subnet: #{network["subnets"].inspect}"
  end

  def validate_network!(network)
    raise Error, "#{NETWORK} is internal; published ports would not work. Remove it and retry" if network["internal"]
    raise Error, "#{NETWORK} has DNS enabled; agents must not resolve names. Remove it and retry" if network["dns_enabled"]
    raise Error, "#{NETWORK} needs the option metric=200 so the default network keeps the default route" unless network.dig("options", "metric") == "200"
    raise Error, "#{NETWORK} exists but is not managed by sandbox-network (label #{NETWORK_LABEL}=shared is missing)" unless network.dig("labels", NETWORK_LABEL) == "shared"

    address = gateway_address(network)
    squatter = (network["containers"] || {}).values.find do |container|
      container["name"] != GATEWAY && container_addresses(container).include?(address)
    end
    raise Error, "#{squatter["name"]} holds #{address}, the gateway's address on #{NETWORK}" if squatter
  end

  def container_addresses(container)
    (container["interfaces"] || {}).values.flat_map { _1["subnets"] || [] }.map { _1["ipnet"].to_s.split("/").first }
  end

  def validate_gateway_owner!(container)
    return if container.dig("Config", "Labels", EGRESS_LABEL) == "gateway"

    raise Error, "A container named #{GATEWAY} exists but is not managed by sandbox-network (label #{EGRESS_LABEL}=gateway is missing); refusing to replace it"
  end

  # Agents are named pipelines-<profile>-<worktree> by attach-worktree. The
  # profile `sandbox` is reserved so no agent can collide with the gateway.
  def validate_container_name!(name)
    return if name.match?(AGENT_NAME_PATTERN) && !name.match?(RESERVED_NAME_PATTERN)

    raise Error, "Invalid agent container name: #{name}"
  end

  # CA and token

  def validate_ca!(ca_dir)
    cert_path = File.join(ca_dir, "ca-cert.pem")
    key_path = File.join(ca_dir, "ca-key.pem")
    raise Error, missing_ca_message(ca_dir) unless File.file?(cert_path) && File.file?(key_path)

    require_private!(key_path, "CA private key")
    key_pem = File.read(key_path)
    raise Error, "#{key_path} must be a PKCS#8 key (BEGIN PRIVATE KEY); recreate it with openssl genpkey" unless key_pem.start_with?("-----BEGIN PRIVATE KEY-----")

    certificate = OpenSSL::X509::Certificate.new(File.read(cert_path))
    key = OpenSSL::PKey.read(key_pem)
    basic_constraints = certificate.extensions.find { _1.oid == "basicConstraints" }
    raise Error, "#{cert_path} is not a CA certificate (basicConstraints CA:TRUE)" unless basic_constraints&.value&.include?("CA:TRUE")
    raise Error, "#{cert_path} does not match #{key_path}" unless certificate.check_private_key(key)
  rescue OpenSSL::OpenSSLError => error
    raise Error, "Unreadable CA in #{ca_dir}: #{error.message}"
  end

  def missing_ca_message(ca_dir)
    <<~MESSAGE.chomp
      The egress CA is missing in #{ca_dir}. Create a dedicated one (never add it to the Keychain):
        mkdir -p -m 700 #{ca_dir}
        openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out #{ca_dir}/ca-key.pem
        chmod 600 #{ca_dir}/ca-key.pem
        openssl req -x509 -new -key #{ca_dir}/ca-key.pem -days 3650 -subj "/CN=pipelines-sandbox CA" -addext basicConstraints=critical,CA:TRUE -out #{ca_dir}/ca-cert.pem
    MESSAGE
  end

  # One fine-grained PAT shared by all agents. Classic and OAuth tokens are
  # refused: `/graphql` is allowed and cannot be path-scoped, so the token's
  # own repository scope is the only limit.
  def read_pat!(path)
    unless File.file?(path)
      raise Error, "GitHub token not found: #{path}. Create a fine-grained PAT for alaexeyshustov/pipelines " \
                   "(see .sandbox/docs/sandbox-network.md) and save it there with mode 600; it must start with github_pat_"
    end

    require_private!(path, "GitHub token")
    token = File.read(path).strip
    return token if token.start_with?("github_pat_")

    raise Error, "#{path} must hold a fine-grained token (github_pat_...): classic and OAuth tokens cannot be limited to one repository, and /graphql cannot be path-scoped"
  end

  def require_private!(path, description)
    return if (File.stat(path).mode & 0o077).zero?

    raise Error, "#{description} #{path} must have mode 600 (chmod 600 #{path})"
  end

  # Agents

  # Everything `podman run` needs to put an agent behind the gateway. Secrets
  # (the PAT and the proxy URL) are passed by name; run-agent sets their values
  # in the environment, never in argv.
  def agent_args(gateway_ip:, ca_cert:)
    [
      "--network", NETWORK, "--dns=none", "--add-host", "#{GATEWAY_HOST}:#{gateway_ip}",
      "--add-host", "#{OLLAMA_HOST}:#{gateway_ip}", "--restart=no", "--http-proxy=false", "--cap-drop", "NET_ADMIN", "--cap-drop", "NET_RAW",
      "--security-opt", "no-new-privileges",
      "--label", "#{EGRESS_LABEL}=gateway",
      "--mount", "type=bind,src=#{ca_cert},dst=/run/sandbox-ca.crt,ro",
      *PROXY_VARIABLES.flat_map { ["--env", _1] },
      "--env", "NO_PROXY=#{NO_PROXY}", "--env", "no_proxy=#{NO_PROXY}",
      "--env", "OLLAMA_API_BASE=#{OLLAMA_API_BASE}", "--env", "GH_TOKEN"
    ]
  end

  # Part of the agent's launch config: a new CA or gateway address replaces
  # running agents, a policy edit does not.
  def agent_fingerprint(gateway_ip:, ca_cert:)
    Digest::SHA256.hexdigest("#{JSON.generate(agent_args(gateway_ip: gateway_ip, ca_cert: ca_cert))}\0#{File.binread(ca_cert)}")
  end

  # Names the gateway's identity: the helper that builds it, its image sources
  # (including the policy) and the CA it signs with.
  def gateway_fingerprint(sandbox_dir:, ca_cert:)
    files = [File.join(sandbox_dir, "bin", "sandbox-network"), File.join(sandbox_dir, "bin", "sandbox_network.rb")]
    files += Dir.glob(File.join(sandbox_dir, "gateway", "**", "*")).select { File.file?(_1) }.sort
    digest = Digest::SHA256.new
    files.each do |file|
      digest << file.delete_prefix("#{sandbox_dir}/") << "\0" << File.binread(file) << "\0"
    end
    digest << File.binread(ca_cert)
    digest.hexdigest
  end

  # State directory

  def prepare_state_dir(dir)
    FileUtils.mkdir_p(dir, mode: 0o700)
    return dir if (File.stat(dir).mode & 0o077).zero?

    raise Error, "#{dir} must have mode 700 (chmod 700 #{dir})"
  end

  def proxy_token(dir)
    path = File.join(dir, "proxy-token")
    atomic_write(path, "#{SecureRandom.hex(32)}\n", 0o600) unless File.file?(path)
    File.read(path).strip
  end

  # The gateway mounts this copy, so editing the policy in an agent's worktree
  # changes nothing until the primary checkout's file does.
  def snapshot_policy(dir, source)
    path = File.join(dir, "policy.json")
    atomic_write(path, File.read(source), 0o644)
    path
  end

  def atomic_write(path, contents, mode)
    temporary = "#{path}.tmp#{Process.pid}"
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) { _1.write(contents) }
    File.rename(temporary, path)
  ensure
    FileUtils.rm_f(temporary) if temporary
  end

  # Podman

  def podman(*args, input: nil)
    stdout, stderr, status = Open3.capture3("podman", *args, stdin_data: input.to_s)
    raise Error, "podman #{args.first(2).join(" ")} failed: #{stderr.strip}" unless status.success?

    stdout
  end

  def podman?(*args)
    _, _, status = Open3.capture3("podman", *args)
    status.success?
  end

  def inspect_json(*args)
    stdout, _, status = Open3.capture3("podman", *args)
    status.success? ? JSON.parse(stdout).first : nil
  end

  def inspect_network = inspect_json("network", "inspect", NETWORK)

  def inspect_gateway = inspect_json("container", "inspect", GATEWAY)

  def ensure_rootful!
    return if podman("info", "--format", "{{.Host.Security.Rootless}}").strip == "false"

    raise Error, "Rootless Podman is not supported: the gateway needs a rootful machine (podman machine set --rootful)"
  end

  # Returns the machine to apply the firewall in.
  def firewall_machine
    # `machine list` omits Rootful; `machine inspect` has it and the SSH port.
    machines = JSON.parse(podman("machine", "inspect")).map do |machine|
      { "Name" => machine["Name"], "Rootful" => machine["Rootful"], "Port" => machine.dig("SSHConfig", "Port") }
    end
    connections = JSON.parse(podman("system", "connection", "list", "--format", "json"))
    validate_firewall_target!(machines: machines, connection_uri: active_connection_uri(connections, ENV.to_h), host_os: RbConfig::CONFIG["host_os"])
  end

  def ensure_network
    network = inspect_network
    unless network
      podman("network", "create", "--disable-dns", "--opt", "metric=200", "--label", "#{NETWORK_LABEL}=shared", NETWORK)
      network = inspect_network or raise Error, "#{NETWORK} was not created"
    end
    validate_network!(network)
    network
  end

  def gateway_run_args(address, fingerprint, state)
    mounts = {
      File.join(state, "proxy-token") => "/run/gateway/token",
      File.join(state, "policy.json") => "/run/gateway/policy.json",
      File.join(state, "ca", "ca-cert.pem") => "/run/ca/ca-cert.pem",
      File.join(state, "ca", "ca-key.pem") => "/run/ca/ca-key.pem"
    }
    [
      "run", "--detach", "--name", GATEWAY, "--init", "--http-proxy=false",
      "--read-only", "--tmpfs", "/tmp:rw,nosuid,nodev,size=64m",
      "--cap-drop", "ALL", "--security-opt", "no-new-privileges", "--sysctl", "net.ipv4.ip_forward=0",
      "--network", "podman", "--network", "#{NETWORK}:ip=#{address}",
      "--label", "#{EGRESS_LABEL}=gateway", "--label", "#{CONFIG_LABEL}=#{fingerprint}",
      *mounts.flat_map { |source, destination| ["--mount", "type=bind,src=#{source},dst=#{destination},ro"] },
      gateway_image(fingerprint)
    ]
  end

  def gateway_image(fingerprint) = "localhost/#{GATEWAY}:#{fingerprint}"

  def build_gateway_image(fingerprint)
    image = gateway_image(fingerprint)
    return if podman?("image", "exists", image)

    gateway_dir = File.join(SANDBOX_DIR, "gateway")
    _, status = Process.wait2(Process.spawn("podman", "build", "--tag", image, gateway_dir, out: $stderr))
    raise Error, "podman build of the gateway image failed" unless status.success?
  end

  # Replaces a gateway built from other sources, starts a stopped one and
  # makes sure it sits on the shared network. Agents are not touched.
  def ensure_gateway(network, fingerprint, state)
    address = gateway_address(network)
    gateway = inspect_gateway
    if gateway
      validate_gateway_owner!(gateway)
      if gateway.dig("Config", "Labels", CONFIG_LABEL) != fingerprint
        podman("rm", "--force", GATEWAY)
        gateway = nil
      end
    end

    if gateway.nil?
      build_gateway_image(fingerprint)
      podman(*gateway_run_args(address, fingerprint, state))
    else
      podman("start", GATEWAY) unless gateway.dig("State", "Status") == "running"
      attached = (inspect_network&.fetch("containers", nil) || {}).values.any? { _1["name"] == GATEWAY }
      podman("network", "connect", "--ip", address, NETWORK, GATEWAY) unless attached
    end
  end

  def wait_until_ready!
    READY_ATTEMPTS.times do
      return if podman?("exec", GATEWAY, "bash", "-c", READY_SCRIPT)

      status = podman("container", "inspect", "--format", "{{.State.Status}}", GATEWAY).strip
      raise Error, "Gateway #{GATEWAY} is #{status}, not running; inspect it with `podman logs #{GATEWAY}`" unless status == "running"

      sleep READY_INTERVAL
    end
    raise Error, "Gateway #{GATEWAY} did not become ready; inspect it with `podman logs #{GATEWAY}`"
  end

  def apply_firewall(machine, interface)
    podman("machine", "ssh", machine, "sudo", "nft", "-f", "-", input: ruleset(interface))
  end

  # Reconciles everything an agent depends on and returns the network's
  # inspect data. Must run before every launch or attach: the firewall does
  # not survive a VM reboot.
  def ensure_all(state)
    ensure_rootful!
    machine = firewall_machine
    ca_dir = File.join(state, "ca")
    validate_ca!(ca_dir)
    # Checked here too, not only at launch, so no attach path starts with a token run-agent would refuse.
    read_pat!(File.join(state, "gh-token"))
    snapshot_policy(state, File.join(SANDBOX_DIR, "gateway", "policy.json"))
    proxy_token(state)
    network = ensure_network
    ensure_gateway(network, gateway_fingerprint(sandbox_dir: SANDBOX_DIR, ca_cert: File.join(ca_dir, "ca-cert.pem")), state)
    wait_until_ready!
    network = inspect_network
    apply_firewall(machine, network.fetch("network_interface"))
    network
  end

  # CLI

  # Policy, token and the helper itself come from the primary checkout, never
  # from a worktree an agent can edit.
  def assert_primary_checkout!
    common, _, status = Open3.capture3("git", "-C", ROOT, "rev-parse", "--path-format=absolute", "--git-common-dir")
    primary = status.success? && File.realpath(File.dirname(common.strip)) == File.realpath(ROOT)
    raise Error, "Run sandbox-network from the primary checkout, not from #{ROOT}" unless primary
  end

  def with_lock(state)
    File.open(File.join(state, "lock"), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    ensure
      lock.flock(File::LOCK_UN)
    end
  end

  def run_agent(container, podman_args)
    validate_container_name!(container)
    # The validated name is the one that runs; a caller --name would bypass it.
    if podman_args.any? { _1 == "--name" || _1.start_with?("--name=") }
      raise Error, "run-agent names the container itself; drop --name from the podman arguments"
    end
    state = prepare_state_dir(state_dir)
    token = read_pat!(File.join(state, "gh-token"))
    network = with_lock(state) { ensure_all(state) }
    proxy = "http://nono:#{proxy_token(state)}@#{GATEWAY_HOST}:3128"
    environment = PROXY_VARIABLES.to_h { [_1, proxy] }
    environment.merge!("NO_PROXY" => NO_PROXY, "no_proxy" => NO_PROXY, "GH_TOKEN" => token)
    arguments = agent_args(gateway_ip: gateway_address(network), ca_cert: File.join(state, "ca", "ca-cert.pem"))
    exec(environment, "podman", "run", "--name", container, *arguments, *podman_args)
  end

  def print_fingerprint(gateway:)
    ca_cert = File.join(state_dir, "ca", "ca-cert.pem")
    raise Error, missing_ca_message(File.dirname(ca_cert)) unless File.file?(ca_cert)

    if gateway
      puts gateway_fingerprint(sandbox_dir: SANDBOX_DIR, ca_cert: ca_cert)
    else
      network = inspect_network or raise Error, "#{NETWORK} does not exist yet; run sandbox-network ensure"
      puts agent_fingerprint(gateway_ip: gateway_address(network), ca_cert: ca_cert)
    end
  end

  def main(argv)
    command, *arguments = argv
    assert_primary_checkout!
    case [command, arguments.first]
    in ["ensure", nil]
      state = prepare_state_dir(state_dir)
      with_lock(state) { ensure_all(state) }
    in ["fingerprint", nil | "--gateway"] if arguments.size <= 1
      print_fingerprint(gateway: arguments.first == "--gateway")
    in ["run-agent", String] then run_agent(arguments.first, arguments.drop(1))
    else raise Error, "Usage: sandbox-network ensure | fingerprint [--gateway] | run-agent CONTAINER [PODMAN_RUN_ARGS...]"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    SandboxNetwork.main(ARGV)
  rescue SandboxNetwork::Error, SystemCallError, JSON::ParserError => error
    warn "Sandbox network error: #{error.message}"
    exit 1
  end
end
