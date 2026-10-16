#!/usr/bin/env bash
# Verifica as dependências do pipeline. Obrigatórias: ffmpeg, ffprobe, python3. Opcional: whisper-cli.
set -u

missing=0
check() { # comando dica obrigatorio(1|0)
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok       %s\n' "$1"
  elif [ "$3" = 1 ]; then
    printf 'FALTANDO %s — instale com: %s\n' "$1" "$2" >&2
    missing=1
  else
    printf 'opcional %s ausente — instale com: %s\n' "$1" "$2"
  fi
}

check ffmpeg "brew install ffmpeg" 1
check ffprobe "brew install ffmpeg" 1
check python3 "brew install python" 1
check whisper-cli "brew install whisper-cpp" 0

exit "$missing"
