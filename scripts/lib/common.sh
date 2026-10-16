#!/usr/bin/env bash
# Funções comuns dos scripts do pipeline. Mensagens em português do Brasil.

# Python no Windows usa a codepage local por padrão; força UTF-8 para acentos.
export PYTHONUTF8=1

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

# Duração em segundos (stdout). Morre se o arquivo não for um vídeo legível.
probe_duration() { # arquivo
  local d
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null) || d=""
  case "$d" in
    ''|N/A) die "não foi possível ler o vídeo: $1" ;;
  esac
  printf '%s\n' "$d"
}

# Morre se o vídeo não tiver faixa de áudio.
require_audio() { # arquivo
  local a
  a=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$1" 2>/dev/null) || a=""
  [ -n "$a" ] || die "o vídeo não tem faixa de áudio: $1"
}
