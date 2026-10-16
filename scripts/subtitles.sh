#!/usr/bin/env bash
# Gera o .srt a partir do transcript e (por padrão) queima a legenda no vídeo.
# Uso: subtitles.sh <video> <transcript.json> <saida.mp4> [--srt-only]
# O .srt fica ao lado da saída (mesmo nome, extensão .srt).
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 3 ] || die "uso: subtitles.sh <video> <transcript.json> <saida.mp4> [--srt-only]"
video="$1"; transcript="$2"; out="$3"; srt_only=0
[ "${4:-}" = "--srt-only" ] && srt_only=1

need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
[ -f "$transcript" ] || die "transcript não encontrado: $transcript"
duration="$(probe_duration "$video")"

srt="${out%.*}.srt"
python3 "$here/transcript_to_srt.py" "$transcript" "$duration" > "$srt" || die "falha ao gerar o SRT"
[ "$srt_only" -eq 1 ] && exit 0

# O filtro `subtitles` exige escapes frágeis para caminhos; rodamos numa pasta
# temporária com nome simples (sub.srt) para evitar problemas com espaços, ':' e aspas.
work="$(tmpdir)"
tmp="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -rf "$work" "$tmp"' EXIT
cp "$srt" "$work/sub.srt"
style="FontName=Arial,FontSize=14,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2,Alignment=2,MarginV=60"
(cd "$work" && ffmpeg -v error -y -i "$video" -vf "subtitles=sub.srt:force_style='${style}'" \
  -c:v libx264 -pix_fmt yuv420p -c:a copy "$tmp") || die "falha ao queimar a legenda"
mv -f "$tmp" "$out"
trap 'rm -rf "$work"' EXIT
