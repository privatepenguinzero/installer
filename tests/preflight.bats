@test "refuses a non-KDE Fedora" {
  f="$BATS_TEST_TMPDIR/os"; printf 'ID=fedora\nVARIANT_ID=workstation\n' > "$f"
  OS_RELEASE="$f" run "$BATS_TEST_DIRNAME/../install.sh" --preflight-only
  [ "$status" -eq 1 ]; [[ "$output" == *"Fedora KDE"* ]]
}

@test "accepts Fedora KDE" {
  f="$BATS_TEST_TMPDIR/os"; printf 'ID=fedora\nVARIANT_ID=kde\n' > "$f"
  OS_RELEASE="$f" run "$BATS_TEST_DIRNAME/../install.sh" --preflight-only
  [ "$status" -eq 0 ]
}
