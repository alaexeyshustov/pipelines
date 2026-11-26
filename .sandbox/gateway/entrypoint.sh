#!/usr/bin/env bash
# Supervises the egress proxy and the host-Ollama relay. The root filesystem is
# read-only, so everything nono writes (config, state, cache) lives under /tmp.

set -euo pipefail

export HOME=/tmp/home
export XDG_CONFIG_HOME=/tmp/xdg/config
export XDG_STATE_HOME=/tmp/xdg/state
export XDG_CACHE_HOME=/tmp/xdg/cache
export XDG_DATA_HOME=/tmp/xdg/data
export XDG_RUNTIME_DIR=/tmp/xdg/runtime
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
mkdir -p -m 700 "$XDG_RUNTIME_DIR"

NONO_PROXY_PASS="$(< /run/gateway/token)"
export NONO_PROXY_PASS

children=()
stop_children() {
  trap - EXIT TERM INT
  [[ ${#children[@]} -eq 0 ]] || kill "${children[@]}" 2>/dev/null || true
}
trap stop_children EXIT
trap 'exit 143' TERM INT

# Verbose, not silent: refusals reach `podman logs` as "proxy request denied".
nono proxy -v --listen 0.0.0.0 --port 3128 \
  --profile /run/gateway/policy.json \
  --proxy-ca-cert /run/ca/ca-cert.pem \
  --proxy-ca-key /run/ca/ca-key.pem &
children+=("$!")

socat TCP-LISTEN:11434,fork,reuseaddr TCP:host.containers.internal:11434 &
children+=("$!")

# Either child dying means a half-working gateway: exit so ensure replaces it.
wait -n || true
printf 'Gateway process exited; stopping\n' >&2
exit 1
