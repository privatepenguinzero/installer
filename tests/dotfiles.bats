setup() { source "$BATS_TEST_DIRNAME/../lib/common.sh"; source "$BATS_TEST_DIRNAME/../lib/dotfiles.sh"; }

@test "require_pass_cli stops with the login command when pass-cli is logged out" {
  pass-cli() { return 1; }
  run require_pass_cli
  [ "$status" -ne 0 ]
  [[ "$output" == *"pass-cli login"* ]]
}

@test "require_pass_cli passes when pass-cli info works" {
  pass-cli() { return 0; }
  run require_pass_cli
  [ "$status" -eq 0 ]
}
