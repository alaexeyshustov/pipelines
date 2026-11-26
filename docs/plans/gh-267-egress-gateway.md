# Plan: egress gateway (nono + local CA) for the agent container (GH #267)

**Status:** planned | One PR | Spec: issue body (design settled)

No Archspec layer applies: `Archspec.rb` scans only `app/` and `lib/`, `.rubocop.yml` excludes `.sandbox/**/*`, and Steep/RBS don't cover `.sandbox`. There is no Gemfile or config change, so `archspec reflect` isn't needed.

Verified while planning:

- nono 0.82.0 `proxy` has `-v`, `--listen`, `--port`, `--profile`, `--proxy-ca-cert` and `--proxy-ca-key`, and reads the password from `NONO_PROXY_PASS`. It refuses `--no-auth` on a non-loopback address and needs a PKCS#8 PEM key.
- `nono profile validate` and `nono why --profile <file> --host <url>` work offline:
  - `"/a/b/**"` does **not** match `/a/b`;
  - `*.actions.githubusercontent.com` matches subdomains;
  - the `{,.git}` brace form is invalid, so the policy needs explicit entries.
- Podman 5.5.1: `podman-machine-default` is rootful, the default connection is `ssh://root@127.0.0.1:<port>` and `Rootless=false`.
- `network inspect` returns `network_interface`, `subnets[].gateway`, `internal`, `dns_enabled` and `containers`. It leaves out `labels` and `options` when they are empty.

## Decisions

- **Test seam:** the real helper runs against a JSON-capable podman stub. There is no environment override for the helper path; an override would be a way around the primary-checkout rule.
  - `.sandbox/test/support/podman` is rewritten in Ruby, like the `gh`/`op` stubs. It keeps `STUB_PODMAN_LOG`, `STUB_PODMAN_IMAGE_MISSING` and `STUB_PODMAN_ENV_LOG`.
  - New knobs:
    - `STUB_PODMAN_STATE_DIR` (stateful: `network create`, `run --detach` and the agent `run` labels are recorded, so a second attach sees `exited`/`running` with matching labels)
    - `STUB_PODMAN_ROOTLESS`, `STUB_PODMAN_CONNECTION_URI`, `STUB_PODMAN_NETWORK_JSON`
    - `STUB_PODMAN_GATEWAY` (`absent|running|exited|unmanaged`), `STUB_GATEWAY_FINGERPRINT`
    - `STUB_PODMAN_GATEWAY_UNREADY`, `STUB_FIREWALL_FAILURE`
    - `STUB_PODMAN_NFT_LOG` (stdin of `machine ssh … nft -f -`)
  - Defaults are a happy path: rootful; one machine whose SSH port matches the default root connection; network present and labelled with subnet `10.89.7.0/24`, gateway `10.89.7.1`, interface `podman7`; gateway running with `STUB_GATEWAY_FINGERPRINT`; exec ready.
- **Fake CA and PAT:** `.sandbox/test/sandbox_fixtures.rb`, which is outside the `*_test.rb` glob.
  - It writes `~/.config/pipelines-sandbox/` (mode 700) into the temp HOME, containing:
    - `ca/ca-cert.pem`
    - `ca/ca-key.pem` (mode 600): a real P-256 CA from Ruby `OpenSSL`, PKCS#8
    - `gh-token` (mode 600) = `github_pat_test`
  - `run_attach` passes `STUB_GATEWAY_FINGERPRINT` from `sandbox-network fingerprint --gateway`.
- **Helper CLI:** `sandbox-network` is a bash wrapper (`exec ruby "$script_dir/sandbox_network.rb" "$@"`). The Ruby side uses only the stdlib: `openssl`, `json`, `open3`, `ipaddr`, `fileutils`.
  - `ensure` takes no container argument, because the network is shared.
  - `run-agent <container> <podman-run-args…>` validates the name, runs `ensure` under the lock, unlocks explicitly, then `exec`s `podman run <agent args> <caller args>`. `exec` keeps the TTY, signals and exit code.
  - `fingerprint` prints the agent fingerprint; `fingerprint --gateway` prints the gateway fingerprint.
  - Pure functions live in `module SandboxNetwork`. The CLI runs only when `__FILE__ == $PROGRAM_NAME`.
- **Primary-checkout guard:** `ROOT` comes from `__dir__`. The helper refuses unless the parent of `git -C ROOT rev-parse --path-format=absolute --git-common-dir` equals `ROOT/..` (realpath). `attach-worktree` calls `$primary_repo_root/.sandbox/bin/sandbox-network`. Run the `.sandbox` suite on the host from the primary checkout.
- **State directory** `~/.config/pipelines-sandbox`: mode 700, refused if wider, `flock` on `lock`.
  - `proxy-token`: the nono password, `SecureRandom.hex(32)`, mode 600, generated once.
  - `policy.json`: an atomic snapshot of the primary checkout's copy.
  - `gh-token` and `ca/` are supplied by the user.
  - The gateway mounts `proxy-token`, `policy.json` and both CA files read-only. Agents mount only `ca/ca-cert.pem` at `/run/sandbox-ca.crt`.
- **CA checks:**
  - Both files must exist. Otherwise the error prints `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256` and `openssl req -x509 -key … -addext basicConstraints=critical,CA:TRUE`. `genpkey` writes PKCS#8 even with LibreSSL.
  - The key must be mode 600 and start with `-----BEGIN PRIVATE KEY-----`.
  - The cert must parse, have `CA:TRUE`, and `cert.check_private_key(key)` must pass.
- **PAT:** `run-agent` reads `gh-token`, which must be mode 600 and start with `github_pat_`. It is passed as `--env GH_TOKEN` by name. The `gh auth token` block at `attach-worktree:137-154` is deleted.
  - The reserved op-secret name regex (`attach-worktree:180`) is extended with `GH_TOKEN`, `HTTPS?_PROXY`, `ALL_PROXY`, `NO_PROXY`, `OLLAMA_API_BASE`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `CURL_CA_BUNDLE`, `REQUESTS_CA_BUNDLE`, `BUNDLE_SSL_CA_CERT`, `GIT_SSL_CAINFO` and `NODE_USE_ENV_PROXY`.
- **Agent args** (one constant template):
  - Network: `--network pipelines-sandbox-net`, `--dns=none`, `--add-host sandbox-gateway:<ip>`
  - Hardening: `--restart=no`, `--http-proxy=false`, `--cap-drop NET_ADMIN --cap-drop NET_RAW`, `--security-opt no-new-privileges`
  - `--label io.pipelines.sandbox.egress=gateway`
  - CA mount: `dst=/run/sandbox-ca.crt,ro`
  - Env by name: `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and their lowercase forms; `NO_PROXY`/`no_proxy=localhost,127.0.0.1,::1,sandbox-gateway`
  - `--env OLLAMA_API_BASE=http://sandbox-gateway:11434/v1`, `--env GH_TOKEN`
  - The proxy URL `http://nono:<token>@sandbox-gateway:3128` is set only in the exec environment, never in argv.
- **Fingerprints:**
  - Agent: `sha256(JSON(agent args with the resolved gateway IP) + ca-cert bytes)`. Attach computes it **after** `ensure` and appends it to `launch_config_tag`.
  - Gateway: `sha256` over `sandbox-network`, `sandbox_network.rb`, every file in `.sandbox/gateway/` (path + bytes) and the CA cert. It goes into the `io.pipelines.sandbox.gateway-config` label and the image tag `localhost/pipelines-sandbox-gateway:<fp>`.
- **Gateway address:** `subnets[0].gateway + 1`, IPv4 only. It is connected with `--ip` under the lock. `ensure` refuses if a non-gateway container holds that address.
- **Name collision:** profile `sandbox` is reserved and refused in:
  - `attach-worktree`;
  - `recreate-worktree` (`container rm --force` by name would otherwise delete the gateway);
  - `db_helper.rb register_container` (`PROFILE_PATTERN` + `RESERVED_PROFILES`);
  - `run-agent`, which also rejects the exact gateway name and anything outside `^pipelines-[a-z0-9]+(-[a-z0-9]+)*$`.
- **Firewall target:** a `podman machine` only, via `podman machine ssh <name> sudo nft -f -`.
  - Exactly one machine, with `Rootful=true`.
  - The active connection (`CONTAINER_HOST` > `CONTAINER_CONNECTION` > the default) must be `ssh://root@{localhost,127.0.0.1}:<machine SSH port>`.
  - Native Linux is refused as unsupported.
- **Ruleset:** a pure `ruleset(interface)`; the interface must match `/\A[a-zA-Z0-9_.-]{1,15}\z/`.

  ```
  add table inet pipelines_sandbox
  flush table inet pipelines_sandbox
  table inet pipelines_sandbox {
    chain input   { type filter hook input priority -20; policy accept;
      iifname "<if>" ct state established,related accept
      iifname "<if>" drop }
    chain forward { type filter hook forward priority -20; policy accept;
      iifname "<if>" ct state established,related accept
      iifname "<if>" drop }
  }
  ```

  There is no allow rule toward the gateway: with `br_netfilter` off, agent→gateway traffic is L2 and never reaches these hooks. No test asserts port-level enforcement toward the gateway.
- **`ensure` order:**
  1. Primary-checkout guard, state directory, lock.
  2. Rootful check (`podman info --format {{.Host.Security.Rootless}}` must be `false`).
  3. Firewall-target check.
  4. CA check.
  5. Policy snapshot; create `proxy-token` if missing.
  6. Network: `network create --disable-dns --opt metric=200 --label io.pipelines.sandbox.network=shared pipelines-sandbox-net` if absent. Refuse if it is internal, DNS-enabled, not `metric=200`, or unlabelled.
  7. Gateway:
     - refuse an unlabelled container with the gateway's name;
     - on a fingerprint mismatch, `rm --force`, build if the image is missing (output to stderr), then `run --detach`;
     - if it isn't running, `start`;
     - if it isn't attached, `network connect --ip`.
  8. Readiness: up to 30 × 0.2 s of `podman exec pipelines-sandbox-gateway bash -c 'exec 3<>/dev/tcp/127.0.0.1/3128 && exec 4<>/dev/tcp/127.0.0.1/11434'`. Fail early if the gateway stops running; the error names `podman logs pipelines-sandbox-gateway`.
  9. Apply the nft ruleset.
- **Gateway run flags:**
  - `--http-proxy=false`, `--read-only`, `--tmpfs /tmp:rw,nosuid,nodev,size=64m`
  - `--cap-drop ALL`, `--security-opt no-new-privileges`, `--sysctl net.ipv4.ip_forward=0`, `--init`
  - `--network podman --network pipelines-sandbox-net:ip=<addr>`
  - The four read-only mounts. Native architecture.
- **Gateway image:** `debian:trixie-slim` with `ca-certificates`, `curl` and `socat`, plus nono 0.82.0 from the release tarballs.
  - The tarball checksums are pinned as `NONO_SHA256_ARM64`/`NONO_SHA256_AMD64` ARGs and checked with `sha256sum --check`, following the rtk pattern rather than the release's `SHA256SUMS.txt`.
  - `entrypoint.sh`:
    - sets `HOME` and `XDG_{CONFIG,STATE,CACHE,DATA,RUNTIME}_*` under `/tmp` and creates them;
    - exports `NONO_PROXY_PASS` from `/run/gateway/token`;
    - starts `nono proxy -v --listen 0.0.0.0 --port 3128 --profile /run/gateway/policy.json --proxy-ca-cert /run/ca/ca-cert.pem --proxy-ca-key /run/ca/ca-key.pem`, with no `--silent` and no `--pass`;
    - starts `socat TCP-LISTEN:11434,fork,reuseaddr TCP:host.containers.internal:11434`;
    - runs `wait -n`, kills its children on TERM/exit, and exits non-zero when either child dies.
- **Policy shape:**
  - Plain-string `allow_domain` entries (CONNECT tunnel) for hosts with no method or path limits.
  - Object entries with `endpoints` for the rest:
    - rubygems ×2 and npm: `GET` and `HEAD` only;
    - GitHub repos: `/o/r`, `/o/r/**`, `/o/r.git`, `/o/r.git/**`;
    - `api.github.com`: `/repos/alaexeyshustov/pipelines`, `/repos/alaexeyshustov/pipelines/**`, `/graphql`.
  - `meta.name` is `pipelines-sandbox-egress`.
- **Session bootstrap:** `configure_sandbox_ca` in `session-common.sh`.
  - Overridable only through `SANDBOX_CA_CERT` (default `/run/sandbox-ca.crt`) and `SANDBOX_CA_STORE` (default `/usr/local/share/ca-certificates`), for tests.
  - Exits 1 when the cert or `HTTPS_PROXY` is missing.
  - Copies the cert to `$SANDBOX_CA_STORE/pipelines-sandbox.crt` and runs `update-ca-certificates`.
  - Exports:
    - `SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`, and the same value for `CURL_CA_BUNDLE`, `REQUESTS_CA_BUNDLE`, `BUNDLE_SSL_CA_CERT` and `GIT_SSL_CAINFO`;
    - `NODE_EXTRA_CA_CERTS=$SANDBOX_CA_CERT`;
    - `NODE_USE_ENV_PROXY=1`;
    - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
  - The proxy variables come from `run-agent`.

## Steps

### 1. Gateway image and policy (red first)

**Files:** `.sandbox/gateway/{Containerfile,entrypoint.sh,policy.json}`

**Red** (`.sandbox/test/sandbox_network_test.rb`, `GatewaySourceTest`):

- `policy.json`:
  - parses;
  - its domain set equals the issue table;
  - the rubygems hosts and npm allow only `GET`/`HEAD`;
  - no path contains `{`;
  - every GitHub repo prefix has both the bare form and the `/**` form.
- If `nono --version` is 0.82.x (otherwise skip):
  - `nono profile validate` passes;
  - `nono why --json` returns `allowed` for:
    - `github.com/alaexeyshustov/pipelines`
    - `…/pipelines.git/info/refs`
    - `api.github.com/repos/alaexeyshustov/pipelines/issues/1`
    - `api.github.com/graphql`
    - `x.actions.githubusercontent.com`
  - and `denied` for:
    - `github.com/openai/codex`
    - `api.github.com/repos/other/repo`
    - `example.com`
- Containerfile:
  - `ARG NONO_VERSION=0.82.0`;
  - both `NONO_SHA256_*` are 64 hex characters;
  - has `sha256sum --check`;
  - no `SHA256SUMS.txt`;
  - installs `socat`.
- `entrypoint.sh`:
  - has `nono proxy -v`, no `--silent`, no `--pass`;
  - sets `HOME` and every `XDG_*` under `/tmp`;
  - uses `--port 3128`;
  - relays 11434 to `host.containers.internal:11434`;
  - has `wait -n`.

**Acceptance:**

- `podman build .sandbox/gateway` succeeds.
- A throwaway `podman run --read-only --tmpfs /tmp --cap-drop ALL` with the four mounts logs the nono banner, and `/dev/tcp/127.0.0.1/3128` connects.

### 2. Helper and podman stub (red first)

**Files:**

- `.sandbox/bin/sandbox-network` (755)
- `.sandbox/bin/sandbox_network.rb`
- `.sandbox/test/support/podman` (rewritten in Ruby)
- `.sandbox/test/sandbox_fixtures.rb`

**Red, unit tests:**

- `ruleset`:
  - has the prelude, the table and both chains at -20;
  - has an established-accept rule and then a drop in each chain;
  - rejects `podman0"; flush ruleset`.
- `gateway_address`: `10.89.7.1` → `10.89.7.2`; an IPv6-only or missing subnet raises.
- Network metadata: refuses `internal`, `dns_enabled`, a wrong or missing `metric` and a missing label. Refuses when another container holds the gateway address.
- Gateway ownership: refuses an unlabelled container named `pipelines-sandbox-gateway`.
- Container name:
  - accepts `pipelines-claude-matt-gh-267-egress-gateway`;
  - rejects `pipelines-sandbox-gateway`, `pipelines-sandbox-x` and `other-name`.
- Firewall target:
  - accepts root on 127.0.0.1 or localhost with a matching port;
  - refuses `core@`, a port mismatch, two machines and `Rootful=false`;
  - honours `CONTAINER_CONNECTION` and `CONTAINER_HOST`;
  - refuses a non-macOS host.
- CA:
  - missing → the message includes `openssl genpkey`;
  - key 644 → refused;
  - SEC1 `BEGIN EC PRIVATE KEY` → refused;
  - cert/key mismatch → refused;
  - fixture → ok.
- PAT:
  - `github_pat_…` → ok;
  - `gho_…` and `ghp_…` → refused, and the message says why (`/graphql` can't be path-scoped);
  - 644 → refused;
  - missing → refused with setup hint.
- Agent args:
  - contain every flag above;
  - contain `dst=/run/sandbox-ca.crt,ro`;
  - never contain `ca-key.pem` or the proxy token.
- Fingerprints:
  - the agent fingerprint changes with the CA cert and the gateway IP, and takes no policy input;
  - the gateway fingerprint, computed over temp copies, changes with the helper, a gateway file, the policy and the CA cert.
- State directory:
  - created with mode 700;
  - an existing 755 directory is refused;
  - `proxy-token` is 600 and stable across calls;
  - the policy snapshot equals the source.

**Red, CLI against the stub:**

- `ensure` on the defaults: no `rm`/`run`, and the nft log equals `ruleset("podman7")`.
- Gateway `absent`: `network`, `build`, then `run --detach … --read-only … --cap-drop ALL … --sysctl net.ipv4.ip_forward=0 … --network pipelines-sandbox-net:ip=10.89.7.2`, with the key mounted read-only.
- Fingerprint mismatch: `rm --force`, then `run`.
- `exited`: `start`.
- Network absent: `network create --disable-dns --opt metric=200 --label io.pipelines.sandbox.network=shared pipelines-sandbox-net`.
- Unmanaged gateway or network: exit 1 with no `rm`/`run`.
- Rootless: exit 1 first.
- Unready and turning `exited`: the error names `podman logs pipelines-sandbox-gateway`.
- Firewall failure: exit 1.
- `run-agent pipelines-sandbox-gateway`: refused.
- `run-agent` from a non-primary copy: refused.
- `run-agent` happy path: the `run` line is logged, and the env log has `HTTPS_PROXY=http://nono:<hex>@sandbox-gateway:3128`, the lowercase and `ALL_PROXY` forms, `NO_PROXY` and `GH_TOKEN=github_pat_test`.

**Acceptance:** the test file is green, and `sandbox-network ensure` on the real machine is idempotent (gateway `Id` unchanged).

### 3. Wire attach, recreate and db_helper (red first)

**Files:**

- `.sandbox/bin/attach-worktree`:
  - require `network_helper="$primary_repo_root/.sandbox/bin/sandbox-network"`;
  - refuse profile `sandbox`;
  - delete the `gh auth token` block and `gh_token_mount`;
  - extend the reserved op-secret names;
  - run `ensure` after the image build and before the container-status inspect (`:220`);
  - compute `launch_config_tag` after `ensure` as `<cksum>-<agent fp 16>[-<op fp 16>]`;
  - launch with `run_agent_container with_op_secrets "$network_helper" run-agent "$container_name" --interactive --tty …`;
  - add the CA/PAT prerequisites to the usage text.
- `.sandbox/bin/recreate-worktree`: refuse profile `sandbox`; the help text says the gateway and network are shared and preserved.
- `.sandbox/bin/db_helper.rb`: `register_container` refuses the reserved profile.
- `.sandbox/test/db_helper_test.rb`:
  - fixtures in `@home_directory` and a per-test `STUB_PODMAN_STATE_DIR`;
  - `run_attach` passes `STUB_GATEWAY_FINGERPRINT`;
  - lookups select `run --interactive`.

**Red:**

- Existing attach tests stay green. The amd64 test asserts the agent build and no gateway build when it is current.
- `test_attach_reconciles_the_gateway_before_inspecting_the_container`: `machine ssh` comes before the container-status inspect.
- `test_attach_restart_and_running_paths_reconcile_first`: with stub state `exited` and then `running`, nft is applied before `start --interactive --attach` and before `attach`.
- `test_attach_launches_through_the_gateway`:
  - the run line has the network, `--dns=none`, `--add-host sandbox-gateway:10.89.7.2`, both cap-drops, `--restart=no`, `--http-proxy=false` and the CA mount;
  - it has no `ca-key.pem`;
  - the env log has `GH_TOKEN=github_pat_test` and `HTTPS_PROXY=…sandbox-gateway:3128`.
- `test_attach_no_longer_asks_host_gh_for_a_token`: the gh stub fails on `auth`, and attach still succeeds.
- Refusals: no `run ` line and the container status stays `created` for:
  - missing CA;
  - key 644;
  - `gh-token` = `ghp_x`;
  - rootless;
  - connection `ssh://root@127.0.0.1:1/…`;
  - an unmanaged gateway;
  - an unlabelled network;
  - a firewall failure.
- `test_attach_launch_config_follows_the_ca_not_the_policy`: a new CA cert changes `io.pipelines.sandbox.launch-config`; a new gateway fingerprint doesn't.
- An op secret named `GH_TOKEN` or `HTTPS_PROXY` is refused.
- These fail:
  - `attach … --profile=sandbox`
  - `recreate-worktree --profile=sandbox --dry-run`
  - `db_helper register_container X sandbox`

**Acceptance:** the full `.sandbox` loop is green from the primary checkout, and `git grep -n 'gh auth token' .sandbox/bin` is empty.

### 4. Session bootstrap (red first)

**Files:**

- `.sandbox/profiles/lib/session-common.sh`: add `configure_sandbox_ca`.
- `.sandbox/profiles/claude-matt/claude-session` and `.sandbox/profiles/claude-omcc/claude-session`: call it first. Images rebuild via the lib hash.

**Red** (`.sandbox/test/session_common_test.rb`):

- Without the cert: exit 1, the message names `/run/sandbox-ca.crt`/attach-worktree, and nothing is installed.
- Without `HTTPS_PROXY`: exit 1.
- Happy path, with a stub `update-ca-certificates`, `SANDBOX_CA_STORE` set to a temp directory and a temp cert: the cert is copied to `pipelines-sandbox.crt`, the stub is called, and every exported variable has its exact value.
- Both `claude-session` scripts call `configure_sandbox_ca` before any other session function (a static check).

**Acceptance:** the file is green, and a rebuilt `claude-matt` image starts a session through the gateway with `bundle install` working.

### 5. Docs and integration test

**Files:**

- `.sandbox/docs/adr/0002-egress-gateway-nono-vm-firewall.md`: the issue's Decision section, the rejected `--internal`, the `br_netfilter` caveat and the limitations.
- `.sandbox/docs/adr/0001-podman-sandbox-for-github-issues.md`:
  - Decision: agents egress only through the gateway (link to ADR 0002); GitHub auth is the shared fine-grained PAT.
  - Consequences: never `podman start` an agent by hand; sessions are replaced on their next attach; old gateway images are not pruned.
  - Usage: one-time CA + PAT setup.
- `.sandbox/docs/sandbox-network.md`:
  - topology;
  - CA setup (exact `openssl` commands, modes 700/600, never in the Keychain);
  - PAT scopes and storage;
  - extending `policy.json`: an example, validating with `nono profile validate` / `nono why --profile`, and the `/x` vs `/x/**` rule;
  - denials via `podman logs pipelines-sandbox-gateway | grep 'proxy request denied'` (`denial_category=host_denied`);
  - Ollama through `sandbox-gateway:11434`;
  - limitations;
  - troubleshooting (rootless, connection mismatch, readiness).
- `.sandbox/test/integration/sandbox_network_integration.rb`. It sits outside the DoD glob and is run with `ruby … <agent-image-tag>`.
  - It refuses while containers labelled `io.pipelines.sandbox.egress=gateway` are running.
  - It starts one disposable agent through `run-agent … --detach --publish 127.0.0.1::3000 --entrypoint bash <image> -c 'source /usr/local/lib/session-common.sh; configure_sandbox_ca; <node http server on 3000>'`.
  - It always removes the agent.

**Acceptance:** `sandbox-network.md` covers CA, PAT, extending the allowlist and denial logs.

### 6. Verification on the rootful machine

Run the integration script and the manual checklist. Record the results (date and versions) in ADR 0002.

**Integration script checks:**

- `curl --noproxy '*' https://example.com` fails.
- `curl https://example.com` returns 403, and the gateway logs `proxy request denied` with `host_denied`.
- `github.com/alaexeyshustov/pipelines` returns 200; `github.com/openai/codex` returns 403.
- `curl -X POST https://rubygems.org/api/v1/gems` and `curl -X PUT https://registry.npmjs.org/x` return 403.
- `getent hosts example.com` fails, and a DNS query to `1.1.1.1` fails.
- TCP to the bridge gateway `:22` and to `192.168.127.254` is blocked.
- `sandbox-gateway:11434` connects.
- `test -e /run/ca/ca-key.pem` fails in the agent.
- The published port answers from the host.
- `ensure` keeps the gateway `Id`.
- After `nft delete table inet pipelines_sandbox`, stop the agent, run `ensure`, start the agent: `--noproxy` still fails.

**Manual, in a real `attach-worktree` session:**

- `bundle install`, `pnpm install`, `rbs collection install`, `bundle-audit check --update`
- `git fetch` and `git push` to a scratch branch
- `gh issue view`, `gh pr create --draft`, `gh run view --log`
- `pnpm exec playwright install chromium`
- A Claude Code prompt
- An app request to Ollama
- A gateway restart after a policy edit, which leaves the session alive

## Checks

- `for t in .sandbox/test/*_test.rb; do ruby "$t" || exit 1; done` (host, primary checkout)
- `ruby .sandbox/test/integration/sandbox_network_integration.rb <image>` (manual, rootful machine)
- `bash -n` on `sandbox-network`, `entrypoint.sh`, `attach-worktree` and `recreate-worktree`
- Not affected: rspec, rubocop, archspec, steep/rbs/rigor, brakeman/bundle-audit, pnpm

## Requirement → step

| Requirement | Step |
|---|---|
| ADR 0002 and the ADR 0001 amendments | 5, 6 |
| Gateway Containerfile/entrypoint/policy: pinned nono, socat, `HOME`/`XDG_*` under `/tmp`, `/dev/tcp` readiness, `-v` without `--silent` | 1, 2 |
| Helper `ensure`/`run-agent`/`fingerprint`, refusals, flock, 700 state directory, primary checkout | 2 |
| Shared non-internal bridge, `--dns=none`, add-host, dual-homed gateway | 2 |
| nft `inet pipelines_sandbox`; established replies; published port | 2, 6 |
| Hardening; rootful/remote refusal | 2, 3 |
| Ollama relay + `OLLAMA_API_BASE` | 1, 2, 6 |
| CA location, modes, refusal + hint, cert-only mount | 2, 3, 5 |
| PAT replaces `gh auth token`; `github_pat_` prefix | 2, 3 |
| Split fingerprints | 2, 3 |
| `ensure` before the status inspect on every attach path | 3 |
| session-common CA/proxy bootstrap, called first | 4 |
| Name collisions | 2, 3 |
| Stub + fixtures | 2, 3 |
| `sandbox-network.md`; one-file allowlist | 1, 5 |
| ACs inside the container | 6 |

## Open questions

1. **`dig` isn't in the profile images.** (a) Add `bind9-dnsutils`, or (b) use `ruby -rresolv` against `1.1.1.1` plus `getent` and reword the AC. Default: (b).
2. **PAT rotation doesn't replace agents.** (a) Document running `recreate-worktree` after a rotation, or (b) add a truncated PAT digest to `launch_config_tag`. Default: (a).
3. **Can the gateway read the 600 key with `--cap-drop ALL`?** Confirmed only by the step 1 smoke run. If it fails: (a) `--user` set to the file's mapped uid, or (b) keep `CAP_DAC_READ_SEARCH`. This is your call.
