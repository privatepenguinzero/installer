#!/usr/bin/env bash
# lib/t480s.sh - settings that only make sense on the ThinkPad T480s.
is_t480s() { [[ "$(cat "${DMI_PRODUCT_FILE:-/sys/class/dmi/id/product_version}" 2>/dev/null)" == "ThinkPad T480s" ]]; }

apply_battery_thresholds() {
  if ! is_t480s; then log "not a T480s: skipping battery thresholds"; return 0; fi
  install_system_files "$REPO/system/t480s"
  sudo systemd-hwdb update
  sudo udevadm trigger --subsystem-match=power_supply
  sudo udevadm settle
  # UPower reads CHARGE_LIMIT only when it adds the battery: a daemon started
  # before the hwdb file existed keeps the 75,80 default
  sudo systemctl restart upower
  sudo busctl call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT0 \
    org.freedesktop.UPower.Device EnableChargeThreshold b true >/dev/null || warn "UPower EnableChargeThreshold failed"
  # udev applies the rule asynchronously: give the threshold a few seconds to land
  local f="${BAT_DIR:-/sys/class/power_supply/BAT0}/charge_control_end_threshold" _
  for _ in {1..10}; do [[ "$(cat "$f" 2>/dev/null)" == 85 ]] && return 0; sleep 0.5; done
  warn "battery end threshold is not 85"
}
