---
status: accepted
---

# Egress gateway for agent containers: nono, a local CA and a VM firewall

Amends [ADR 0001](0001-podman-sandbox-for-github-issues.md). Ported from the
propstack `.codex` toolkit, trimmed for this repository. Operating guide:
[sandbox-network.md](../sandbox-network.md).

## Context

Agents run Claude Code with `--dangerously-skip-permissions`. With no permission
prompts, the network is the main exfiltration path: a prompt injection could
send source code or secrets to an arbitrary host. Before this change the agent
container had unrestricted outbound access and the host's full-scope
`gh auth token`.

## Decision

- **Proxy: `nono proxy` with TLS interception.** One shared container,
  `pipelines-sandbox-gateway`, runs nono (version and checksums pinned in
  `.sandbox/gateway/Containerfile`) with a dedicated local CA. A CONNECT-only
  proxy such as Squid can filter by host but not by method or path; interception
  gives host + method + path rules (for example `GET` only on the gem
  registries, one repository on GitHub). npm is the exception: nono refuses
  intercepted paths with an encoded slash, and pnpm requests every scoped
  package as `/@scope%2Fname`, so `registry.npmjs.org` is tunnelled.
  `cdn.playwright.dev` redirects Chrome for Testing to `storage.googleapis.com`,
  which is open only for `GET`/`HEAD` under `/chrome-for-testing-public/`. nono refuses `--no-auth` on a
  non-loopback bind, so the proxy requires a token (`proxy-token`, generated
  once, passed to agents by name).
- **One shared, non-internal bridge** `pipelines-sandbox-net`
  (`--disable-dns`, `metric=200`, labelled `io.pipelines.sandbox.network=shared`).
  The gateway joins it and the default network; agents join only the sandbox
  bridge, with `--dns=none` and `--add-host sandbox-gateway:<ip>`. The metric
  keeps the gateway's default route on the default network. There is no
  per-agent network lifecycle, so there is no `release`.
- **Enforcement: a VM-owned nftables table `inet pipelines_sandbox`**, applied
  in the Podman machine with `podman machine ssh <name> sudo nft -f -`. It
  matches only the labelled bridge (`iifname`), accepts established/related
  replies (so the published app port keeps working) and drops every new
  connection that is routed (`forward`) or aimed at the VM/host (`input`). It is
  reloaded idempotently (`add` + `flush` of its own table) and never touches
  Netavark's tables.
- **`podman network create --internal` is rejected.** It removes the default
  route, which breaks published-port return traffic, and it injects an NXDOMAIN
  resolver into the dual-homed gateway (propstack findings).
- **`br_netfilter` caveat.** With `br_netfilter` off, agent-to-gateway traffic
  is switched at L2 and never reaches the nft hooks. Isolation toward the
  gateway therefore rests on what listens there: nono on 3128, the Ollama relay
  on 11434, and `net.ipv4.ip_forward=0` in the gateway so it cannot route agent
  traffic onward.
- **Rootful Podman is required.** The helper refuses rootless Podman, a machine
  that is not rootful, more or fewer than one machine, and an active connection
  that is not `ssh://root@{localhost,127.0.0.1}:<machine port>` (a mismatched
  remote engine). Native Linux is not supported.
- **Hardening.** Agents: `--restart=no`, `--cap-drop NET_ADMIN --cap-drop NET_RAW`,
  `no-new-privileges`, `--http-proxy=false`. Gateway: `--read-only` with a `/tmp`
  tmpfs, `--cap-drop ALL`, `no-new-privileges`. Only the CA certificate is
  mounted in agents (`/run/sandbox-ca.crt`); the key is mounted read-only into
  the gateway only.
- **Dedicated CA** at `~/.config/pipelines-sandbox/ca/` (ECDSA P-256, PKCS#8,
  key mode 600), never added to the Keychain, so a leaked key cannot
  impersonate sites for the host. The helper refuses to start without it.
- **One fine-grained PAT shared by all agents** in
  `~/.config/pipelines-sandbox/gh-token`, replacing `gh auth token`. It is
  scoped to `alaexeyshustov/pipelines`. `/graphql` is allowed but cannot be
  path-scoped, so the token's own repository scope is the real limit; the helper
  refuses anything not starting with `github_pat_`.
- **Split fingerprints.** The agent fingerprint (run-agent arguments including
  the gateway address, plus the CA certificate) is part of `launch_config_tag`.
  The gateway fingerprint (helper, `.sandbox/gateway/*` including the policy, CA
  certificate) is only a label on the gateway and part of its image tag. A
  policy edit recreates just the gateway and leaves sessions alive; a new CA or
  gateway address replaces agents.
- **Host Ollama relay.** The gateway runs `socat` from `:11434` to
  `host.containers.internal:11434`; agents get
  `OLLAMA_API_BASE=http://sandbox-gateway.internal:11434/v1`. The `.internal`
  alias is needed because Ollama refuses a Host that isn't local.
- **The helper runs from the primary checkout only.** The policy and proxy
  token are snapshotted into the state directory (mode 700, `flock`), so an
  agent editing its worktree copy changes nothing.

## Consequences

- Every attach path reconciles the gateway and nft rules first. The table does
  not survive a VM reboot, so agents must never be started by hand.
- The first attach after this change builds the gateway image (slow once).

### Limitations

- Allowed hosts are still leak paths: the model APIs (Anthropic, OpenAI,
  Mistral) and Google APIs accept any caller's key, and GitHub is limited by the
  PAT's repository scope rather than by path. Credential injection (nono
  `--credential`) is a follow-up. npm is tunnelled, so `npm publish` isn't
  blocked by the gateway (it needs an npm token the agent doesn't have).
- No agent-to-agent isolation: all agents share one bridge and can reach each
  other's dev servers. Accepted for a single-user setup.
- IMAP and other non-HTTP protocols are dropped; use the Gmail API adapter.
- Gemini is not allowed (add `generativelanguage.googleapis.com` if needed).
- macOS with one rootful `podman machine` only.
- The host and the Podman VM administrator remain trusted.

## Verification

2026-11-27, macOS 26.7.2, Podman 5.5.1 client / 5.5.2 server (rootful
`podman-machine-default`, VM kernel 6.12.13), nono 0.82.0, agent image
`pipelines-claude-matt-agent-amd64:eef854c8…`.

`sandbox_network_integration.rb`: all 15 checks pass. Direct egress, DNS
lookups and TCP to the bridge gateway and VM host fail. `example.com` gets a
403 logged as `host_denied`, `github.com/openai/codex` a 403, a `POST` to
RubyGems a 403. This repository, scoped npm metadata and Ollama through
`OLLAMA_API_BASE` answer 200. The CA key is absent in the agent, the published
port answers from the host, `ensure` keeps the gateway `Id` and restores a
deleted nft table.

Session checks, in a throwaway agent on a clone of the branch, through the
gateway: `bundle install`, `pnpm install`, `rbs collection install`,
`bundle-audit update`, `git fetch`, `gh issue view`, `gh run view --log`,
`playwright install chromium`, `claude -p` and an Ollama request all pass.
`git push` and `gh pr create` were not exercised.

The run found the npm `%2F` and Ollama Host problems described above, and that
`run-agent` didn't name the container it validated (fixed: it now passes
`--name` and refuses a caller's).
