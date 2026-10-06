#!/usr/bin/env bash
# lib/packages.sh - dnf installs. No --skip-unavailable: a missing package must stop the run.

# missing_rpms NAME... - prints each name that is not installed.
missing_rpms() { local p; for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || echo "$p"; done; }

# upgrade_system - bring a fresh install up to date first: half-upgraded KDE
# packages (kmime -> kf6-kmime) otherwise conflict with the list's dependencies.
upgrade_system() {
  local rc=0
  sudo dnf5 -q check-upgrade >/dev/null || rc=$?
  case $rc in
    0) mark_ok "system up to date" ;;
    100) retry sudo dnf5 -y upgrade || die "dnf upgrade failed"; mark_changed "upgraded the system" ;;
    *) die "dnf could not check for updates" ;;
  esac
}

install_dnf_list() {
  local -a want missing
  mapfile -t want < <(read_list "$1")
  mapfile -t missing < <(missing_rpms "${want[@]}")
  if (( ${#missing[@]} == 0 )); then mark_ok "dnf packages (${#want[@]})"; return; fi
  log "Installing ${#missing[@]} packages: ${missing[*]}"
  retry sudo dnf5 -y install "${missing[@]}" || die "dnf could not install: ${missing[*]}"
  mark_changed "installed ${#missing[@]} dnf packages"
}

install_codecs() {
  if rpm -q ffmpeg gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-plugin-libav >/dev/null 2>&1; then
    mark_ok "codecs"; return
  fi
  if rpm -q ffmpeg-free >/dev/null 2>&1; then
    retry sudo dnf5 -y swap ffmpeg-free ffmpeg --allowerasing || die "could not swap ffmpeg-free for ffmpeg"
  else
    retry sudo dnf5 -y install ffmpeg --allowerasing || die "could not install ffmpeg"
  fi
  retry sudo dnf5 -y install --allowerasing --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin \
    gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-plugin-libav x264-libs \
    || die "could not install the GStreamer plugins"
  mark_changed "installed codecs"
}

install_node24() {
  if [[ "$(node --version 2>/dev/null)" == v24.* ]]; then mark_ok "Node 24"; return; fi
  retry sudo dnf5 -y install --allowerasing nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin || die "could not install Node 24"
  [[ "$(node --version)" == v24.* ]] || die "expected Node 24, got $(node --version)"
  mark_changed "installed Node 24"
}
