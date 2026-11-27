# Sandbox egress gateway

Agents started by `.sandbox/bin/attach-worktree` reach the network only through
one shared gateway, `pipelines-sandbox-gateway`, which runs `nono proxy` with a
dedicated CA and the allowlist in `.sandbox/gateway/policy.json`. Rationale and
limits: [ADR 0002](adr/0002-egress-gateway-nono-vm-firewall.md).

Requires a rootful `podman machine` (the only one), the active Podman connection
pointing at it, and macOS. Nothing else needs installing: the helper is Ruby
stdlib, nono runs inside the gateway image.

## Topology

```text
agent A --+
          +-- pipelines-sandbox-net --+-- gateway (nono :3128, Ollama relay :11434)
agent B --+   (no DNS, metric=200)     |        |
                                       |        +-- default network -- allowed HTTPS hosts
                                       |        +-- host.containers.internal:11434 (Ollama)
browser -- 127.0.0.1:<port> -- agent:3000
```

The VM table `inet pipelines_sandbox` matches only the sandbox bridge: replies
to established connections pass (the published app port), new connections that
are routed or aimed at the VM/host are dropped. Agent-to-gateway traffic is L2
and bypasses nft (`br_netfilter` is off); it is limited by the gateway's
listeners and `ip_forward=0`. Bypassing the proxy variables therefore gets an
agent nowhere: there is no DNS and no route.

## One-time setup

State lives in `~/.config/pipelines-sandbox` (mode 700; the helper refuses
anything wider):

```text
~/.config/pipelines-sandbox/
  ca/ca-cert.pem    CA certificate (agents get this one only)
  ca/ca-key.pem     CA key, mode 600 (gateway only)
  gh-token          fine-grained PAT, mode 600
  policy.json       snapshot of .sandbox/gateway/policy.json (generated)
  proxy-token       nono password, mode 600 (generated once; delete it to
                    rotate, and the next attach replaces the gateway and agent)
  lock              flock file
```

### CA

A dedicated CA, never added to the macOS Keychain (the host must not trust it):

```bash
mkdir -p -m 700 ~/.config/pipelines-sandbox/ca
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
  -out ~/.config/pipelines-sandbox/ca/ca-key.pem
chmod 600 ~/.config/pipelines-sandbox/ca/ca-key.pem
openssl req -x509 -new -key ~/.config/pipelines-sandbox/ca/ca-key.pem -days 3650 \
  -subj "/CN=pipelines-sandbox CA" -addext basicConstraints=critical,CA:TRUE \
  -out ~/.config/pipelines-sandbox/ca/ca-cert.pem
chmod 700 ~/.config/pipelines-sandbox
```

`genpkey` writes a PKCS#8 key (`BEGIN PRIVATE KEY`), which the helper requires.
Replacing the CA changes both fingerprints: the gateway is rebuilt and agents
are replaced on their next attach.

### GitHub token

Create a fine-grained PAT, resource owner `alaexeyshustov`, repository
`alaexeyshustov/pipelines` only, with:

| Permission | Access |
|---|---|
| Contents | Read and write |
| Issues | Read and write |
| Pull requests | Read and write |
| Actions | Read |
| Metadata | Read |

```bash
install -m 600 /dev/null ~/.config/pipelines-sandbox/gh-token
pbpaste > ~/.config/pipelines-sandbox/gh-token   # or edit the file
```

It must start with `github_pat_`: `/graphql` is allowed and cannot be
path-scoped, so only a fine-grained token's repository scope limits GitHub
access. It is passed to agents as `GH_TOKEN`. After rotating it, run
`.sandbox/bin/recreate-worktree <issue>` for each existing sandbox.

## Extending the allowlist

Edit `.sandbox/gateway/policy.json` in the **primary checkout** (the helper
snapshots that copy; a worktree copy has no effect). A host is either a bare
string (all methods, all paths) or an object with endpoint rules:

```json
{
  "domain": "pypi.org",
  "endpoints": [
    { "method": "GET", "path": "/" },
    { "method": "GET", "path": "/**" }
  ]
}
```

Rules for paths:

- `/x` matches only `/x`; `/x/**` matches everything below it, not `/x`
  itself. List both (`/` and `/**`, or `/x` and `/x/**`).
- No brace patterns (`/x/{a,b}`): list each variant. Git repositories need both
  `/owner/repo/**` and `/owner/repo.git/**`.
- Use `"method": "*"` for any method.

Validate before attaching:

```bash
nono profile validate .sandbox/gateway/policy.json
nono why --profile .sandbox/gateway/policy.json --host https://pypi.org/simple/rake/   # ALLOWED
nono why --profile .sandbox/gateway/policy.json --host https://example.com             # DENIED
```

The next `attach-worktree` (or `sandbox-network ensure`) sees the new gateway
fingerprint, builds the new image, then replaces only the gateway. Running agent
sessions stay up; their connections drop briefly while the gateway restarts.

## Reading denials

```bash
podman logs pipelines-sandbox-gateway 2>&1 | grep 'proxy request denied'
```

The line carries the host, method, path and a `denial_category`
(`host_denied` for an unlisted host). A 403 in the agent with no matching line
did not come from the gateway. For path or method denials, compare the request
against the endpoint rules with `nono why --host <url>`.

nono refuses any intercepted path containing an encoded slash (`%2F`) with
`denial_category=endpoint_policy`, whatever the rules say, and `nono why`
does not show this. A host whose clients send such paths has to be a plain
(tunnelled) entry. That's why `registry.npmjs.org` is plain: pnpm fetches
every scoped package as `/@scope%2Fname`.

## Ollama

Agents reach the host's Ollama at `http://sandbox-gateway.internal:11434/v1`
(`OLLAMA_API_BASE`); the gateway relays to `host.containers.internal:11434`.
The `.internal` alias matters: Ollama answers 403 to a Host header that isn't
local, and it accepts `*.internal`. Ollama must be listening on a host address
Podman's VM can reach. The alias is in `NO_PROXY`, so the request bypasses nono.

## Limitations

- Allowed hosts remain leak paths (model and Google APIs accept any key); GitHub
  is limited by the PAT's repository scope.
- npm is tunnelled, so the gateway doesn't block `npm publish`; it needs an
  npm token the agent doesn't have. RubyGems stays `GET`/`HEAD` only.
- All agents share one bridge and can reach each other's dev servers.
- IMAP and other non-HTTP protocols do not work; Gemini is not allowed.
- Never `podman start` an agent by hand: the nft table does not survive a VM
  reboot and only `attach-worktree` reconciles it.
- Running sessions are replaced on their next attach after a launch-config
  change (new CA, gateway address, run-agent arguments).
- Old gateway images are not pruned (`podman images localhost/pipelines-sandbox-gateway`).

## Troubleshooting

All messages are prefixed `Sandbox network error:`.

| Message | Fix |
|---|---|
| `The egress CA is missing in …` | Run the CA commands above. |
| `… must have mode 600 (chmod 600 …)` | `chmod 600` the key or token; `chmod 700` the state directory. |
| `… must be a PKCS#8 key` / `is not a CA certificate` / `does not match` | Recreate the CA with the commands above. |
| `GitHub token not found` / `must hold a fine-grained token` | Create the PAT as above; classic and OAuth tokens are refused. |
| `Rootless Podman is not supported` | `podman machine set --rootful`, restart the machine. |
| `Expected exactly one podman machine` / `must be rootful` | Keep one machine, rootful. |
| `The active Podman connection … is not the local rootful machine` | Unset `CONTAINER_HOST`/`CONTAINER_CONNECTION` or use `podman system connection default <machine>-root`. |
| `… exists but is not managed by sandbox-network` | A container or network with the gateway's name is not ours; remove or rename it. |
| `… is internal` / `has DNS enabled` / `needs the option metric=200` | `podman network rm pipelines-sandbox-net`; it is recreated on the next attach. |
| `Gateway … did not become ready` | `podman logs pipelines-sandbox-gateway` (the entrypoint exits if nono or the relay dies). |
| `Run sandbox-network from the primary checkout` | Run the helpers from the main checkout, not a worktree. |

After a VM reboot, agents are not restarted: run `attach-worktree` again. It
reconciles the gateway and firewall before the agent starts.
