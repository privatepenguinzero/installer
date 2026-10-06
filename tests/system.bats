setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/system.sh"
  sudo() { "$@"; }
  restorecon() { :; }
}

@test "add_cifs_mount appends the line once" {
  FSTAB="$BATS_TEST_TMPDIR/fstab"; : > "$FSTAB"; CIFS_MOUNTPOINT="$BATS_TEST_TMPDIR/mnt"
  add_cifs_mount; add_cifs_mount
  [ "$(grep -c '//<ha-host>/config' "$FSTAB")" -eq 1 ]
}

@test "install_system_files copies once and then reports nothing" {
  src="$BATS_TEST_TMPDIR/src"; ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$src/etc/x"; echo a > "$src/etc/x/f.conf"
  install_system_files "$src"
  [ "$(cat "$ROOT/etc/x/f.conf")" = a ]
  [ "${#CHANGED[@]}" -eq 1 ]
  CHANGED=(); install_system_files "$src"
  [ "${#CHANGED[@]}" -eq 0 ]
}

@test "enable_services stops when a service cannot be enabled" {
  systemctl() { [[ $1 == is-enabled ]] && return 1; [[ $* == *libvirtd* ]] && return 1; return 0; }
  sudo() { "$@"; }
  run enable_services
  [ "$status" -ne 0 ]; [[ "$output" == *libvirtd* ]]
}
