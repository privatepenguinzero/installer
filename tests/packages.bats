setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/packages.sh"
  sudo() { "$@"; }
  CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
}

@test "upgrade_system upgrades when updates are pending" {
  dnf5() { echo "$*" >> "$CALLS"; [[ $* == *check-upgrade* ]] && return 100; return 0; }
  upgrade_system
  grep -q '^-y upgrade' "$CALLS"
  [ "${#CHANGED[@]}" -eq 1 ]
}

@test "upgrade_system does nothing on an up-to-date system" {
  dnf5() { echo "$*" >> "$CALLS"; return 0; }
  upgrade_system
  ! grep -q '^-y upgrade' "$CALLS" || false
  [ "${#CHANGED[@]}" -eq 0 ]
}

@test "upgrade_system stops when dnf cannot check for updates" {
  dnf5() { return 1; }
  run upgrade_system
  [ "$status" -ne 0 ]
}

@test "install_codecs leaves an installed codec set alone" {
  rpm() { shift; local p; for p in "$@"; do
    case $p in ffmpeg|gstreamer1-plugins-bad-freeworld|gstreamer1-plugins-ugly|gstreamer1-plugin-libav) ;; *) return 1 ;; esac
  done; }
  dnf5() { echo "$*" >> "$CALLS"; }
  install_codecs
  [ ! -s "$CALLS" ]
}
