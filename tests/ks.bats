@test "rendered kickstart validates and contains no placeholders or plaintext password" {
  out="$BATS_TEST_TMPDIR/t.ks"
  KS_SSHKEY='ssh-ed25519 AAAAtest k@t' "$BATS_TEST_DIRNAME/../install/render-ks" "$out"
  ! grep -q '@[A-Z_]*@' "$out" || false
  grep -qx 'sshpw --username=root --sshkey "ssh-ed25519 AAAAtest k@t"' "$out"
  # anaconda finds a reused btrfs volume by --name (blivet names it after its label)
  grep -qx 'btrfs none --noformat --name=fedora btrfs.01' "$out"
  grep -qx 'btrfs /home --subvol --name=home --noformat fedora' "$out"
  # without it os-release has no VARIANT_ID=kde and install.sh refuses the system
  grep -qx 'dnf -y swap fedora-release-identity-basic fedora-release-identity-kde' "$out"
  # a text-mode install otherwise leaves multi-user.target as the default
  grep -qx 'xconfig --startxonboot' "$out"
  ! grep -E '^(rootpw|user)' "$out" | grep -qE '(password=|rootpw --iscrypted )icenoir( |$)' || false
  run podman run --rm -v "$out:/t.ks:ro,Z" registry.fedoraproject.org/fedora:44 \
    bash -c 'dnf -yq install pykickstart >/dev/null && ksvalidator -v F44 /t.ks'
  echo "$output"; [ "$status" -eq 0 ]
}
