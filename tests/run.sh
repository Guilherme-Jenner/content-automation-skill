#!/usr/bin/env bash
# Executa tests/test_*.sh (filtrados por padrão opcional). Cada função test_* roda em subshell.
# Uso: bash tests/run.sh [padrão]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
export PYTHONUTF8=1
export CLO_ALLOW_TEST_NOW=1   # só os testes podem fixar o relógio (--now)
pattern="${1:-}"
total=0; failed=0

for file in "$ROOT"/tests/test_*.sh; do
  case "$file" in *"$pattern"*) ;; *) continue ;; esac
  printf '%s\n' "${file#"$ROOT"/}"
  # shellcheck disable=SC2013
  for fn in $(grep -oE '^test_[a-z0-9_]+' "$file"); do
    total=$((total + 1))
    out=$(
      CLO_TEST_FAILED=0
      # shellcheck source=/dev/null
      . "$ROOT/tests/lib/assert.sh"
      # shellcheck source=/dev/null
      . "$file" || { echo "erro ao carregar $file (sintaxe?)"; exit 1; }
      [ "$(type -t "$fn")" = function ] || { echo "função $fn não foi definida (erro de sintaxe no arquivo?)"; exit 1; }
      "$fn"
      exit "$CLO_TEST_FAILED"
    ) 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '  ok   %s\n' "$fn"
    else
      failed=$((failed + 1))
      printf '  FAIL %s\n%s\n' "$fn" "$out"
    fi
  done
done

printf '\n%d testes, %d falhas\n' "$total" "$failed"
[ "$failed" -eq 0 ] && [ "$total" -gt 0 ]
