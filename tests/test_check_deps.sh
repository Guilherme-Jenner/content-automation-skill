#!/usr/bin/env bash
# Testes de scripts/check-deps.sh

test_reports_missing_ffmpeg() {
  local empty out status
  empty="$(mktemp -d)"
  out=$(PATH="$empty" "$BASH" "$ROOT/scripts/check-deps.sh" 2>&1)
  status=$?
  rmdir "$empty"
  [ "$status" -ne 0 ] || _fail "deveria falhar sem ffmpeg"
  assert_contains "$out" "brew install ffmpeg" "dica de instalação"
}
