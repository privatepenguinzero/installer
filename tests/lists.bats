# Resolves every dnf.txt entry against the real repos inside fedora:44.
# Slow (~3 min) but it is the test that catches a renamed package.
@test "every dnf.txt entry resolves" {
  run podman run --rm -v "$BATS_TEST_DIRNAME/..:/src:Z" registry.fedoraproject.org/fedora:44 bash -c '
    set -e
    dnf -yq install dnf5-plugins >/dev/null
    sudo() { "$@"; }
    source /src/lib/common.sh; source /src/lib/repos.sh
    RETRY_DELAY=5 setup_dnf >/dev/null
    want=$(read_list /src/lists/dnf.txt | sort -u)
    have=$(dnf5 -q repoquery --qf "%{name}\n" $want | sort -u)
    missing=$(comm -23 <(echo "$want") <(echo "$have"))
    [ -z "$missing" ] || { echo "unresolved: $missing"; exit 1; }'
  echo "$output"
  [ "$status" -eq 0 ]
}
