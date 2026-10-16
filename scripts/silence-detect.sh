#!/usr/bin/env bash
# Propõe um plano de cortes (approved=false) removendo silêncios do vídeo.
# Uso: silence-detect.sh <video> <saida.json> [--min-silence 0.6] [--noise -35dB] [--pad 0.15]
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: silence-detect.sh <video> <saida.json> [--min-silence S] [--noise dB] [--pad S]"
video="$1"; out="$2"; shift 2
min_silence=0.6; noise=-35dB; pad=0.15
while [ $# -gt 0 ]; do
  case "$1" in
    --min-silence) min_silence="${2:?}"; shift 2 ;;
    --noise) noise="${2:?}"; shift 2 ;;
    --pad) pad="${2:?}"; shift 2 ;;
    *) die "opção desconhecida: $1" ;;
  esac
done

need_cmd ffmpeg "brew install ffmpeg"
need_cmd ffprobe "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
duration="$(probe_duration "$video")"
require_audio "$video"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
log="$(ffmpeg -hide_banner -nostats -i "$video" -af "silencedetect=noise=${noise}:d=${min_silence}" -f null - 2>&1)" \
  || die "falha ao analisar o áudio: $video"
status=0
printf '%s\n' "$log" | python3 "$here/silence_to_cutplan.py" "$video" "$duration" "$pad" > "$tmp" || status=$?
[ "$status" -eq 0 ] || exit "$status"
mv "$tmp" "$out"
trap - EXIT
