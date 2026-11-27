#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual end-to-end check of the egress gateway (GH #267) on the rootful Podman
# machine. Not part of the *_test.rb suite: it needs the real CA and PAT in
# ~/.config/pipelines-sandbox, builds/reconciles the real gateway, and runs one
# disposable agent.
#
#   ruby .sandbox/test/integration/sandbox_network_integration.rb <agent-image-tag>
#
# Run it from the primary checkout. Prints PASS/FAIL per check; exits 1 on any FAIL.

require "json"
require "net/http"
require "open3"

ROOT = File.expand_path("../../..", __dir__)
HELPER = File.join(ROOT, ".sandbox", "bin", "sandbox-network")
GATEWAY = "pipelines-sandbox-gateway"
LABEL = "io.pipelines.sandbox.egress=gateway"
AGENT = "pipelines-nettest-#{Process.pid}"
TABLE = "inet pipelines_sandbox"

IMAGE = ARGV.fetch(0) { abort "Usage: ruby #{$PROGRAM_NAME} <agent-image-tag>" }

# Serves on 3000 once the CA is installed; node ships in the profile images.
AGENT_SCRIPT = <<~'BASH'
  source /usr/local/lib/session-common.sh
  configure_sandbox_ca
  exec node -e 'require("http").createServer((_, r) => r.end("sandbox-ok")).listen(3000, "0.0.0.0")'
BASH

$failures = 0

def run(*command)
  stdout, stderr, status = Open3.capture3(*command)
  [stdout, stderr, status.success?]
end

def check(name)
  passed, detail = yield
  puts "#{passed ? "PASS" : "FAIL"}  #{name}#{detail ? " (#{detail})" : ""}"
  $failures += 1 unless passed
rescue StandardError => error
  puts "FAIL  #{name} (#{error.class}: #{error.message})"
  $failures += 1
end

def podman(*args) = run("podman", *args)

# Runs inside the agent; returns [stdout, success].
def agent(*command, name: AGENT)
  stdout, _, ok = podman("exec", name, *command)
  [stdout.strip, ok]
end

def http_code(*curl_args)
  out, = agent("curl", "-sS", "--max-time", "20", "-o", "/dev/null", "-w", "%{http_code}", *curl_args)
  out
end

def tcp_blocked?(host, port)
  script = "require 'socket'; begin; Socket.tcp(ARGV[0], ARGV[1].to_i, connect_timeout: 4).close; exit 1; rescue StandardError; exit 0; end"
  _, blocked = agent("ruby", "-e", script, host, port.to_s)
  blocked
end

def gateway_id = podman("container", "inspect", "--format", "{{.Id}}", GATEWAY).first.strip

def machine_name = JSON.parse(podman("machine", "inspect").first).first.fetch("Name")

def start_agent
  _, stderr, ok = run(HELPER, "run-agent", AGENT, "--detach", "--platform", "linux/amd64",
                      "--publish", "127.0.0.1::3000", "--entrypoint", "bash", IMAGE, "-c", AGENT_SCRIPT)
  abort "run-agent failed: #{stderr}" unless ok
  wait_for_server
end

def wait_for_server
  60.times do
    _, ok = agent("curl", "-sS", "--max-time", "2", "http://127.0.0.1:3000")
    return if ok
    sleep 0.5
  end
  # The agent is removed on exit, so show its logs now.
  logs, = podman("logs", AGENT)
  abort "The agent's server on :3000 did not come up. Agent logs:\n#{logs}"
end

running, = podman("ps", "--filter", "label=#{LABEL}", "--format", "{{.Names}}")
agents = running.split - [GATEWAY]
abort "Refusing to run while agents are running: #{agents.join(", ")}" unless agents.empty?

begin
  start_agent
  puts "Agent #{AGENT} (#{IMAGE}) is up"

  check("curl --noproxy '*' https://example.com fails") do
    _, ok = agent("curl", "-sS", "--max-time", "8", "--noproxy", "*", "https://example.com")
    [!ok]
  end

  # A host nono doesn't intercept is refused at CONNECT, so the 403 is the
  # proxy's reply (%{http_connect}); %{http_code} stays 000.
  check("https://example.com is refused with 403 and logged as host_denied") do
    code, = agent("curl", "-sS", "--max-time", "20", "-o", "/dev/null", "-w", "%{http_connect}", "https://example.com")
    logs = podman("logs", GATEWAY).then { _1[0] + _1[1] }
    denied = logs.lines.grep(/proxy request denied/).any? { _1.include?("host_denied") && _1.include?("example.com") }
    [code == "403" && denied, "status #{code}, logged #{denied}"]
  end

  check("github.com/alaexeyshustov/pipelines is allowed (200)") do
    code = http_code("https://github.com/alaexeyshustov/pipelines")
    [code == "200", "status #{code}"]
  end

  check("github.com/openai/codex is denied (403)") do
    code = http_code("https://github.com/openai/codex")
    [code == "403", "status #{code}"]
  end

  check("POST rubygems.org/api/v1/gems is denied (403)") do
    code = http_code("-X", "POST", "https://rubygems.org/api/v1/gems")
    [code == "403", "status #{code}"]
  end

  # npm is tunnelled: nono refuses intercepted paths with %2F, which pnpm uses
  # for every scoped package.
  check("scoped npm package metadata is allowed (200)") do
    code = http_code("https://registry.npmjs.org/@pnpm%2Fexe")
    [code == "200", "status #{code}"]
  end

  check("getent hosts example.com fails") do
    _, ok = agent("getent", "hosts", "example.com")
    [!ok]
  end

  check("DNS query to 1.1.1.1 fails") do
    script = "require 'resolv'; begin; r = Resolv::DNS.new(nameserver: ['1.1.1.1']); r.timeouts = 3; r.getaddress('example.com'); exit 1; rescue StandardError; exit 0; end"
    _, blocked = agent("ruby", "-e", script)
    [blocked]
  end

  network = JSON.parse(podman("network", "inspect", "pipelines-sandbox-net").first).first
  bridge_gateway = network.fetch("subnets").first.fetch("gateway")

  check("TCP to the bridge gateway #{bridge_gateway}:22 is blocked") { [tcp_blocked?(bridge_gateway, 22)] }
  check("TCP to the VM host 192.168.127.254:22 is blocked") { [tcp_blocked?("192.168.127.254", 22)] }

  # Needs Ollama running on the host; Ollama itself refuses a non-local Host.
  check("Ollama answers through OLLAMA_API_BASE (200)") do
    code, = agent("bash", "-c", 'curl -sS --max-time 10 -o /dev/null -w "%{http_code}" "${OLLAMA_API_BASE%/v1}/api/tags"')
    [code == "200", "status #{code}"]
  end

  check("/run/ca/ca-key.pem is absent in the agent") do
    _, exists = agent("test", "-e", "/run/ca/ca-key.pem")
    [!exists]
  end

  check("the published port answers from the host") do
    mapping = podman("port", AGENT, "3000/tcp").first.lines.first.to_s.strip
    host_port = mapping.split(":").last.to_i
    body = Net::HTTP.get(URI("http://127.0.0.1:#{host_port}")) rescue nil
    [body == "sandbox-ok", mapping]
  end

  check("ensure keeps the gateway Id") do
    before = gateway_id
    _, stderr, ok = run(HELPER, "ensure")
    after = gateway_id
    [ok && before == after, ok ? nil : stderr.strip]
  end

  check("ensure restores a deleted nft table and --noproxy still fails after a restart") do
    machine = machine_name
    _, _, deleted = podman("machine", "ssh", machine, "sudo", "nft", "delete", "table", *TABLE.split)
    podman("stop", "--time", "2", AGENT)
    _, stderr, ok = run(HELPER, "ensure")
    _, _, table = podman("machine", "ssh", machine, "sudo", "nft", "list", "table", *TABLE.split)
    podman("start", AGENT)
    wait_for_server
    _, direct = agent("curl", "-sS", "--max-time", "8", "--noproxy", "*", "https://example.com")
    [deleted && ok && table && !direct, ok ? nil : stderr.strip]
  end
ensure
  podman("rm", "--force", "--time", "2", AGENT)
end

puts $failures.zero? ? "All checks passed" : "#{$failures} check(s) failed"
exit($failures.zero? ? 0 : 1)
