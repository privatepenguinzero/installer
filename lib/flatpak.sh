#!/usr/bin/env bash
# lib/flatpak.sh
install_flatpak_list() {
  flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  local -a want missing
  mapfile -t want < <(read_list "$1")
  mapfile -t missing < <(comm -23 <(printf '%s\n' "${want[@]}" | sort) <(flatpak list --app --columns=application | sort))
  if (( ${#missing[@]} == 0 )); then mark_ok "flatpaks (${#want[@]})"; return; fi
  retry flatpak install -y --user --noninteractive flathub "${missing[@]}" || die "flatpak could not install: ${missing[*]}"
  mark_changed "flatpak installed: ${missing[*]}"
}
