#!/usr/bin/env bash
# Funções comuns dos scripts do pipeline. Mensagens em português do Brasil.

die() { # mensagem
  printf 'erro: %s\n' "$1" >&2
  exit 1
}

need_cmd() { # comando dica
  command -v "$1" >/dev/null 2>&1 || die "'$1' não encontrado. Instale com: $2"
}

tmpdir() {
  mktemp -d 2>/dev/null || mktemp -d -t clo
}
