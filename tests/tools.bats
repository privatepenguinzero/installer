setup() {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/tools.sh"
}

@test "want_version matches a binary's reported version" {
  bin="$BATS_TEST_TMPDIR/fake"; printf '#!/bin/sh\necho "fake 1.2.3"\n' > "$bin"; chmod +x "$bin"
  run want_version "$bin" 1.2.3
  [ "$status" -eq 0 ]
  run want_version "$bin" 9.9.9
  [ "$status" -ne 0 ]
}

@test "want_version fails for a missing binary" {
  run want_version /nonexistent 1.0
  [ "$status" -ne 0 ]
}

@test "every pinned version has a checksum" {
  [ -n "$PASS_CLI_VERSION" ] && [ ${#PASS_CLI_SHA256} -eq 64 ]
  [ -n "$PAY_RESPECTS_VERSION" ] && [ ${#PAY_RESPECTS_SHA256} -eq 64 ]
  [ -n "$NERDFONT_VERSION" ] && [ ${#NERDFONT_SHA256} -eq 64 ]
}
