#!/usr/bin/env bash
# Propõe um plano de cortes (approved=false) removendo silêncios do vídeo.
# Uso: silence-detect.sh <video> <saida.json> [--min-silence 0.6] [--noise -35dB] [--pad 0.15] [--force]
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: silence-detect.sh <video> <saida.json> [--min-silence S] [--noise dB] [--pad S]"
video="$(abspath "$1")"; out="$(abspath "$2")"; shift 2
min_silence=0.6; noise=-35dB; pad=0.15; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --min-silence) [ $# -ge 2 ] || die "--min-silence exige um valor (segundos)"; min_silence="$2"; shift 2 ;;
    --noise) [ $# -ge 2 ] || die "--noise exige um valor (ex.: -35dB)"; noise="$2"; shift 2 ;;
    --pad) [ $# -ge 2 ] || die "--pad exige um valor (segundos)"; pad="$2"; shift 2 ;;
    --force) force=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done

need_cmd ffmpeg "brew install ffmpeg"
need_cmd ffprobe "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
duration="$(probe_duration "$video")"
require_min_duration "$video"
require_audio "$video"
refuse_existing "$out" "$force"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
log="$(ffmpeg -hide_banner -nostats -i "$video" -af "silencedetect=noise=${noise}:d=${min_silence}" -f null - 2>&1)" \
  || die "falha ao analisar o áudio: $video"
status=0
printf '%s\n' "$log" | python3 "$here/silence_to_cutplan.py" "$video" "$duration" "$pad" > "$tmp" || status=$?
[ "$status" -eq 0 ] || exit "$status"
mv "$tmp" "$out"
trap - EXIT
