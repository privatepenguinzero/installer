M="$BATS_TEST_DIRNAME/../bin/migrate-home-paths"
setup() {
  export CLAUDE_DIR="$BATS_TEST_TMPDIR/claude" CLAUDE_JSON="$BATS_TEST_TMPDIR/claude.json"
  mkdir -p "$CLAUDE_DIR/projects/-var-home-icenoir/memory" "$CLAUDE_DIR/projects/-var-home-icenoir-personale-x"
  echo note > "$CLAUDE_DIR/projects/-var-home-icenoir/memory/a.md"
  echo '{"projects":{"/var/home/icenoir":{},"/var/home/icenoir/personale/x":{}}}' > "$CLAUDE_JSON"
  echo '{"note":"/var/home/icenoir/coding"}' > "$CLAUDE_DIR/settings.json"
}

@test "renames project dirs and rewrites json paths" {
  run "$M"; [ "$status" -eq 0 ]
  [ -f "$CLAUDE_DIR/projects/-home-icenoir/memory/a.md" ]
  [ -d "$CLAUDE_DIR/projects/-home-icenoir-personale-x" ]
  [ ! -e "$CLAUDE_DIR/projects/-var-home-icenoir" ]
  grep -q '"/home/icenoir/personale/x"' "$CLAUDE_JSON"
  ! grep -q /var/home "$CLAUDE_JSON" "$CLAUDE_DIR/settings.json" || false
  [ -f "$CLAUDE_JSON.pre-migration" ]
}

@test "second run is a no-op" {
  "$M"; run "$M"; [ "$status" -eq 0 ]; [[ "$output" == *"nothing to migrate"* ]]
}

@test "refuses when a target dir already exists, and changes nothing" {
  mkdir -p "$CLAUDE_DIR/projects/-home-icenoir"
  run "$M"; [ "$status" -eq 3 ]
  [ -d "$CLAUDE_DIR/projects/-var-home-icenoir" ]
  grep -q /var/home "$CLAUDE_JSON"
}
