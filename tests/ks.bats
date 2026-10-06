@test "rendered kickstart validates and contains no placeholders or plaintext password" {
  out="$BATS_TEST_TMPDIR/t.ks"
  "$BATS_TEST_DIRNAME/../install/render-ks" "$out"
  ! grep -q '@[A-Z_]*@' "$out"
  ! grep -E '^(rootpw|user)' "$out" | grep -qE '(password=|rootpw --iscrypted )icenoir( |$)'
  run podman run --rm -v "$out:/t.ks:ro,Z" registry.fedoraproject.org/fedora:44 \
    bash -c 'dnf -yq install pykickstart >/dev/null && ksvalidator -v F44 /t.ks'
  echo "$output"; [ "$status" -eq 0 ]
}
