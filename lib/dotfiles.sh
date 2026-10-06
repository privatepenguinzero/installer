#!/usr/bin/env bash
# lib/dotfiles.sh
export PROTON_PASS_LINUX_KEYRING=dbus

require_pass_cli() {
  pass-cli info >/dev/null 2>&1 && return 0
  warn "pass-cli is not logged in, and chezmoi needs it for ~/.ssh/id_ed25519."
  warn "Run:  PROTON_PASS_LINUX_KEYRING=dbus pass-cli login   then rerun ./install.sh"
  return 1
}

apply_dotfiles() {
  require_pass_cli || exit 2
  if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
    retry chezmoi update --apply && mark_ok "dotfiles (updated)"
  else
    retry chezmoi init --apply privatepenguinzero/dotfiles && mark_changed "applied dotfiles"
  fi
}
