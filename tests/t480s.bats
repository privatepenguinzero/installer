setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/system.sh"
  source "$BATS_TEST_DIRNAME/../lib/t480s.sh"
}

@test "is_t480s is true on the T480s" {
  DMI_PRODUCT_FILE="$BATS_TEST_TMPDIR/p"; echo "ThinkPad T480s" > "$DMI_PRODUCT_FILE"
  run is_t480s; [ "$status" -eq 0 ]
}

@test "on a VM, is_t480s is false and the battery step is skipped without failing" {
  DMI_PRODUCT_FILE="$BATS_TEST_TMPDIR/p"; echo "pc-q35-9.0" > "$DMI_PRODUCT_FILE"
  run is_t480s; [ "$status" -ne 0 ]
  run apply_battery_thresholds; [ "$status" -eq 0 ]; [[ "$output" == *"not a T480s"* ]]
}

@test "on the T480s a threshold that lands late does not warn" {
  DMI_PRODUCT_FILE="$BATS_TEST_TMPDIR/p"; echo "ThinkPad T480s" > "$DMI_PRODUCT_FILE"
  BAT_DIR="$BATS_TEST_TMPDIR/BAT0"; mkdir -p "$BAT_DIR"; echo 100 > "$BAT_DIR/charge_control_end_threshold"
  sudo() { :; }; install_system_files() { :; }
  ( sleep 1; echo 85 > "$BAT_DIR/charge_control_end_threshold" ) &
  run apply_battery_thresholds
  [ "$status" -eq 0 ]; [[ "$output" != *"is not 85"* ]]
}

@test "on the T480s UPower is restarted after the hwdb update and before thresholds are enabled" {
  DMI_PRODUCT_FILE="$BATS_TEST_TMPDIR/p"; echo "ThinkPad T480s" > "$DMI_PRODUCT_FILE"
  BAT_DIR="$BATS_TEST_TMPDIR/BAT0"; mkdir -p "$BAT_DIR"; echo 85 > "$BAT_DIR/charge_control_end_threshold"
  CALLS="$BATS_TEST_TMPDIR/calls"; sudo() { echo "$*" >> "$CALLS"; }; install_system_files() { :; }
  apply_battery_thresholds
  # UPower reads CHARGE_LIMIT only when it adds the battery, so a running daemon keeps 75,80
  grep -n "" "$CALLS" | grep -E "hwdb update|restart upower|EnableChargeThreshold" | cut -d: -f2- > "$BATS_TEST_TMPDIR/order"
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/order")" = "systemd-hwdb update" ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/order")" = "systemctl restart upower" ]
  [[ "$(sed -n 3p "$BATS_TEST_TMPDIR/order")" == *EnableChargeThreshold* ]]
}
