setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  RETRY_DELAY=0
}

@test "read_list strips comments and blank lines" {
  f="$BATS_TEST_TMPDIR/l.txt"
  printf 'git\n\n# a comment\n  curl   # trailing\n' > "$f"
  run read_list "$f"
  [ "$status" -eq 0 ]
  [ "$output" = $'git\ncurl' ]
}

@test "retry succeeds once the command does" {
  n="$BATS_TEST_TMPDIR/n"; echo 0 > "$n"
  flaky() { c=$(( $(cat "$n") + 1 )); echo "$c" > "$n"; [ "$c" -ge 3 ]; }
  run retry flaky
  [ "$status" -eq 0 ]
  [ "$(cat "$n")" -eq 3 ]
}

@test "retry gives up after RETRY_MAX attempts" {
  RETRY_MAX=2
  run retry false
  [ "$status" -ne 0 ]
}

@test "verify_sha256 accepts the right hash and rejects a wrong one" {
  f="$BATS_TEST_TMPDIR/x"; printf 'abc' > "$f"
  run verify_sha256 "$f" ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  [ "$status" -eq 0 ]
  run verify_sha256 "$f" 0000000000000000000000000000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
}

@test "summary says nothing changed when CHANGED is empty" {
  CHANGED=(); UNCHANGED=("dnf packages")
  run summary
  [[ "$output" == *"nothing changed"* ]]
}

@test "summary lists changes" {
  CHANGED=("installed niri"); UNCHANGED=()
  run summary
  [[ "$output" == *"installed niri"* ]]
}
