setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/system.sh"
  sudo() { "$@"; }
  restorecon() { :; }
}

@test "add_cifs_mount appends the line once" {
  FSTAB="$BATS_TEST_TMPDIR/fstab"; : > "$FSTAB"; CIFS_MOUNTPOINT="$BATS_TEST_TMPDIR/mnt"
  HA_SMB_HOST=192.0.2.10
  add_cifs_mount; add_cifs_mount
  [ "$(grep -c '^//192.0.2.10/config /mnt/homeassistant cifs ' "$FSTAB")" -eq 1 ]
}

@test "add_cifs_mount skips without HA_SMB_HOST and leaves fstab alone" {
  FSTAB="$BATS_TEST_TMPDIR/fstab"; : > "$FSTAB"; CIFS_MOUNTPOINT="$BATS_TEST_TMPDIR/mnt"
  unset HA_SMB_HOST
  run add_cifs_mount
  [ "$status" -eq 0 ]
  [[ "$output" == *local.env* ]]
  [ ! -s "$FSTAB" ]
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

@test "ensure_graphical_boot switches a text-mode default to graphical, once" {
  STATE="$BATS_TEST_TMPDIR/target"; echo multi-user.target > "$STATE"
  systemctl() { case $1 in get-default) cat "$STATE" ;; set-default) echo "$2" > "$STATE" ;; esac; }
  ensure_graphical_boot
  [ "$(cat "$STATE")" = graphical.target ]
  [ "${#CHANGED[@]}" -eq 1 ]
  CHANGED=(); ensure_graphical_boot
  [ "${#CHANGED[@]}" -eq 0 ]
}

@test "ensure_zsh_login switches a bash login shell to zsh, once" {
  STATE="$BATS_TEST_TMPDIR/shell"; echo /bin/bash > "$STATE"
  getent() { echo "icenoir:x:1000:1000::/home/icenoir:$(cat "$STATE")"; }
  usermod() { [ "$1" = -s ] && echo "$2" > "$STATE"; }
  ensure_zsh_login
  [ "$(cat "$STATE")" = /bin/zsh ]
  [ "${#CHANGED[@]}" -eq 1 ]
  CHANGED=(); ensure_zsh_login
  [ "${#CHANGED[@]}" -eq 0 ]
}

@test "install_system_files keeps the executable bit and fixes a wrong mode" {
  src="$BATS_TEST_TMPDIR/src"; ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$src/usr/local/bin"; printf '#!/bin/sh\n' > "$src/usr/local/bin/t"; chmod 755 "$src/usr/local/bin/t"
  install_system_files "$src"
  [ "$(stat -c %a "$ROOT/usr/local/bin/t")" = 755 ]
  chmod 644 "$ROOT/usr/local/bin/t"; CHANGED=()
  install_system_files "$src"
  [ "$(stat -c %a "$ROOT/usr/local/bin/t")" = 755 ]
  [ "${#CHANGED[@]}" -eq 1 ]
}

@test "setup_autologin writes user, default session and sudo rule once" {
  ROOT="$BATS_TEST_TMPDIR/root"; USER=alice
  visudo() { :; }
  setup_autologin
  grep -qx 'User=alice' "$ROOT/etc/plasmalogin.conf.d/10-autologin.conf"
  grep -qx 'Session=niri.desktop' "$ROOT/etc/plasmalogin.conf.d/20-autologin-session.conf"
  grep -q '^alice ALL=(root) NOPASSWD: /usr/local/libexec/switch-session-apply niri, ' "$ROOT/etc/sudoers.d/switch-session"
  [ "$(stat -c %a "$ROOT/etc/sudoers.d/switch-session")" = 440 ]
  CHANGED=(); setup_autologin
  [ "${#CHANGED[@]}" -eq 0 ]
}

@test "setup_autologin keeps the session switch-session chose" {
  ROOT="$BATS_TEST_TMPDIR/root"; USER=alice
  visudo() { :; }
  mkdir -p "$ROOT/etc/plasmalogin.conf.d"
  printf '[Autologin]\nSession=plasma.desktop\n' > "$ROOT/etc/plasmalogin.conf.d/20-autologin-session.conf"
  setup_autologin
  grep -qx 'Session=plasma.desktop' "$ROOT/etc/plasmalogin.conf.d/20-autologin-session.conf"
}

@test "setup_autologin stops when the sudo rule does not validate" {
  ROOT="$BATS_TEST_TMPDIR/root"; USER=alice
  visudo() { return 1; }
  run setup_autologin
  [ "$status" -ne 0 ]
  [ ! -e "$ROOT/etc/sudoers.d/switch-session" ]
}

@test "setup_remote_desktop enables both services and KRDP PAM login" {
  log="$BATS_TEST_TMPDIR/log"
  systemctl() { echo "systemctl $*" >> "$log"; [[ $2 != is-enabled ]]; }
  kreadconfig6() { echo false; }
  kwriteconfig6() { echo "kwriteconfig6 $*" >> "$log"; }
  openssl() { echo "openssl $*" >> "$log"; touch "$BATS_TEST_TMPDIR/data/krdpserver/krdp.crt" "$BATS_TEST_TMPDIR/data/krdpserver/krdp.key"; }
  XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  setup_remote_desktop
  grep -q 'systemctl --global enable wayvnc.service' "$log"
  grep -q 'systemctl --global enable app-org.kde.krdpserver.service' "$log"
  grep -q 'kwriteconfig6 --file krdpserverrc --group General --key SystemUserEnabled true' "$log"
  grep -q "kwriteconfig6 --file krdpserverrc --group General --key Certificate $XDG_DATA_HOME/krdpserver/krdp.crt" "$log"
  grep -q "CertificateKey $XDG_DATA_HOME/krdpserver/krdp.key" "$log"
}
