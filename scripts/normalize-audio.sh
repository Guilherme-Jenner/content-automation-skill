#!/usr/bin/env bash
# Normaliza o áudio para ~-14 LUFS (loudnorm em duas passagens). O vídeo é copiado sem re-encode.
# Uso: normalize-audio.sh <video> <saida.mp4> [--force]
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: normalize-audio.sh <video> <saida.mp4>"
force=0; args=()
for a in "$@"; do if [ "$a" = "--force" ]; then force=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || die "uso: normalize-audio.sh <video> <saida.mp4> [--force]"
video="$(abspath "$1")"; out="$(abspath "$2")"
need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
probe_duration "$video" >/dev/null
require_audio "$video"
refuse_existing "$out" "$force"

target="I=-14:TP=-1.5:LRA=11"
log="$(ffmpeg -hide_banner -nostats -i "$video" -af "loudnorm=${target}:print_format=json" -f null - 2>&1)" \
  || die "falha ao medir o áudio de $video"
params="$(printf '%s\n' "$log" | python3 -c "
import sys, json, re
t = sys.stdin.read()
m = json.loads(re.search(r'\{[^{}]*\"input_i\"[^{}]*\}', t, re.S).group(0))
print(f\"measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}\")")" \
  || die "não foi possível ler a medição de loudness"

case "$params" in
  *measured_I=-inf*|*measured_I=-Inf*) die "o áudio de $video é silêncio total (nada para normalizar): $video" ;;
esac

tmp="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -f "$tmp"' EXIT
ffmpeg -v error -y -i "$video" -af "loudnorm=${target}:${params}:linear=true" \
  -c:v copy -c:a aac -ar 48000 "$tmp" || die "falha ao normalizar o áudio"
mv -f "$tmp" "$out"
trap - EXIT
