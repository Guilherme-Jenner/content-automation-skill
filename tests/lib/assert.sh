#!/usr/bin/env bash
# Asserts mínimos para os testes. Cada falha imprime a mensagem e marca o teste como falho.

# shellcheck disable=SC2034
_fail() { printf '    FALHA: %s\n' "$1" >&2; CLO_TEST_FAILED=1; }

assert_eq() { # esperado atual mensagem
  [ "$1" = "$2" ] || _fail "${3:-assert_eq}: esperado '$1', obtido '$2'"
}

assert_file_exists() { [ -f "$1" ] || _fail "arquivo não existe: $1"; }

assert_contains() { # texto trecho mensagem
  case "$1" in *"$2"*) ;; *) _fail "${3:-assert_contains}: '$2' não encontrado em '$1'" ;; esac
}

assert_fails() { # comando...
  if "$@" >/dev/null 2>&1; then _fail "esperava falha, mas passou: $*"; fi
}

assert_near() { # esperado atual tolerância mensagem
  if ! python3 -c "import sys; sys.exit(0 if abs(float('$1')-float('$2'))<=float('$3') else 1)"; then
    _fail "${4:-assert_near}: esperado $1 ±$3, obtido $2"
  fi
}
