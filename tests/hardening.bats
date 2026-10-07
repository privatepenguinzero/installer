setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/system.sh"
  sudo() { "$@"; }
  S="$BATS_TEST_DIRNAME/../system/common/etc"
}

@test "hardening files skip the settings that break this laptop" {
  ! grep -qE '^(net\.ipv4\.conf\.[a-z]+\.rp_filter|kernel\.modules_disabled)' "$S/sysctl.d/90-hardening.conf" || false
  ! grep -qiE '^\s*(MaxSessions|Port)\b' "$S/ssh/sshd_config.d/30-hardening.conf" || false
  ! grep -qE '^[^#]*usb[-_]storage' "$S/modprobe.d/90-hardening.conf" || false
  grep -qx 'kernel.yama.ptrace_scope = 1' "$S/sysctl.d/90-hardening.conf"
  grep -qx 'MaxAuthTries 3' "$S/ssh/sshd_config.d/30-hardening.conf"
  grep -qx 'install dccp /bin/false' "$S/modprobe.d/90-hardening.conf"
}

@test "tighten_cron_perms restricts cron files once" {
  ROOT="$BATS_TEST_TMPDIR/r"; mkdir -p "$ROOT/etc/cron.monthly"
  : > "$ROOT/etc/crontab"; chmod 644 "$ROOT/etc/crontab"; chmod 755 "$ROOT/etc/cron.monthly"
  tighten_cron_perms
  [ "$(stat -c %a "$ROOT/etc/crontab")" = 600 ]
  [ "$(stat -c %a "$ROOT/etc/cron.monthly")" = 700 ]
  [ "${#CHANGED[@]}" -eq 1 ]
  CHANGED=(); tighten_cron_perms
  [ "${#CHANGED[@]}" -eq 0 ]
}
