#!/usr/bin/env bash
# Reenquadra o vídeo para 1080x1920 (9:16) sem esticar a imagem.
# Uso: reframe-9x16.sh <video> <saida.mp4> [--mode blur|crop] [--force]
#   blur (padrão): vídeo inteiro centralizado sobre fundo desfocado
#   crop: preenche o quadro e corta as sobras
# A rotação gravada pelo celular (metadado) é aplicada automaticamente pelo ffmpeg.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; args=()
for a in "$@"; do if [ "$a" = "--force" ]; then force=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || die "uso: reframe-9x16.sh <video> <saida.mp4> [--mode blur|crop] [--force]"
video="$(abspath "$1")"; out="$(abspath "$2")"; mode=blur
if [ "${3:-}" = "--mode" ]; then [ $# -ge 4 ] || die "--mode exige um valor"; mode="$4"; fi
case "$mode" in
  blur) filter="[0:v]split[a][b];[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:5[bg];[b]scale=1080:1920:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1[v]" ;;
  crop) filter="[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1[v]" ;;
  *) die "modo inválido: $mode (use blur ou crop)" ;;
esac

need_cmd ffmpeg "brew install ffmpeg"
[ -f "$video" ] || die "arquivo não encontrado: $video"
probe_duration "$video" >/dev/null
refuse_existing "$out" "$force"

tmp="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -f "$tmp"' EXIT
ffmpeg -v error -y -i "$video" -filter_complex "$filter" -map "[v]" -map "0:a?" \
  -c:v libx264 -pix_fmt yuv420p -c:a copy "$tmp" || die "falha ao reenquadrar $video"
mv -f "$tmp" "$out"
trap - EXIT
