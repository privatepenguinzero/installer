#!/usr/bin/env bash
# install.sh - turn a fresh Fedora KDE install into the full desktop. Safe to rerun.
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
export REPO
for lib in common repos packages tools flatpak system dotfiles t480s; do
  # shellcheck source=/dev/null
  source "$REPO/lib/$lib.sh"
done

check_os() {
  # shellcheck source=/dev/null
  . "${OS_RELEASE:-/etc/os-release}"
  [[ "${ID:-}" == fedora && "${VARIANT_ID:-}" == kde ]] || die "this script targets Fedora KDE (found ${ID:-?}/${VARIANT_ID:-?})"
}

if [[ "${1:-}" == --preflight-only ]]; then check_os; exit 0; fi
check_os
[[ $EUID -ne 0 ]] || die "run as your user, not root"
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

log "1/8 dnf and repositories"; setup_dnf
log "2/8 system packages";      upgrade_system; install_dnf_list "$REPO/lists/dnf.txt"; install_codecs; install_node24
log "3/8 tools outside dnf";    install_brew; install_brew_list "$REPO/lists/brew.txt"; install_github_tools; install_cursor; install_claude
log "4/8 flatpaks";             install_flatpak_list "$REPO/lists/flatpak.txt"
log "5/8 services and system";  install_system_files "$REPO/system/common"; enable_services; ensure_graphical_boot; ensure_zsh_login; add_cifs_mount; recolor_papirus
log "6/8 home path migration"
if out=$("$REPO/bin/migrate-home-paths"); then
  if [[ "$out" == "nothing to migrate" ]]; then mark_ok "Claude paths"; else mark_changed "$out"; fi
else
  die "migrate-home-paths refused; see the message above"
fi
if [[ ! -e /var/home ]]; then sudo ln -s /home /var/home; mark_changed "linked /var/home -> /home"; fi
log "7/8 dotfiles";             apply_dotfiles
log "8/8 machine-specific";     apply_battery_thresholds
summary
