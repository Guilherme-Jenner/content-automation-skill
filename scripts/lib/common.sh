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

# Caminho absoluto sem exigir que o arquivo exista (scripts que mudam de diretório precisam disso).
abspath() { # caminho
  case "$1" in
    /* | [A-Za-z]:[\\/]*) printf '%s\n' "$1" ;;   # inclui C:\... e C:/... (caminhos que o Python imprime no Windows)
    *) printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

# Morre se o vídeo tiver menos de 1 s (não há o que editar).
require_min_duration() { # arquivo
  local d
  d="$(probe_duration "$1")"
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 1.0 else 1)" "$d" \
    || die "o vídeo tem menos de 1 s ($d s): $1"
}

# Morre se a saída já existir e --force não foi dado.
refuse_existing() { # saida force(0|1)
  if [ -e "$1" ] && [ "$2" -eq 0 ]; then
    die "a saída já existe: $1 (use --force para sobrescrever)"
  fi
}
