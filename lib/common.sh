#!/usr/bin/env bash
# lib/common.sh - helpers shared by every step of install.sh.

CHANGED=()
UNCHANGED=()

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# retry CMD... - rerun CMD until it succeeds, up to RETRY_MAX times.
# Exists because a single slow Fedora or RPM Fusion mirror used to kill the
# whole penguinos build (run 37360965896).
# Locals are prefixed because bash scoping is dynamic: a plain "n" would
# shadow a variable of the same name inside the command being retried.
retry() {
  local _retry_max=${RETRY_MAX:-5} _retry_delay=${RETRY_DELAY:-10} _retry_n=1 _retry_rc
  while true; do
    "$@" && return 0
    _retry_rc=$?
    (( _retry_n >= _retry_max )) && return "$_retry_rc"
    warn "attempt $_retry_n/$_retry_max failed: $*; retrying in ${_retry_delay}s"
    sleep "$_retry_delay"
    _retry_n=$(( _retry_n + 1 ))
  done
}

CURL_RETRY=(--retry 5 --retry-all-errors --retry-max-time 180 --connect-timeout 30)

# fetch URL DEST
fetch() { curl -fsSL "${CURL_RETRY[@]}" -o "$2" "$1"; }

# verify_sha256 FILE HEX
verify_sha256() { [[ -f "$1" && "$(sha256sum "$1" | cut -d' ' -f1)" == "$2" ]]; }

# read_list FILE - entries one per line, comments and blank lines dropped.
read_list() { sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }

mark_changed() { CHANGED+=("$*"); }
mark_ok()      { UNCHANGED+=("$*"); }

summary() {
  log "Summary"
  if (( ${#CHANGED[@]} == 0 )); then
    echo "  nothing changed"
  else
    printf '  changed: %s\n' "${CHANGED[@]}"
  fi
  if (( ${#UNCHANGED[@]} )); then printf '  already in place: %s\n' "${UNCHANGED[@]}"; fi
  return 0
}

# Machine-local settings kept out of this public repo (LAN addresses). chezmoi
# installs the file; see README.
LOCAL_ENV=${INSTALLER_ENV:-$HOME/.config/installer/local.env}
# shellcheck source=/dev/null
if [[ -f "$LOCAL_ENV" ]]; then source "$LOCAL_ENV"; fi
