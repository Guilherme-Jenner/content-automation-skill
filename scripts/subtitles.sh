#!/usr/bin/env bash
# Gera o .srt a partir do transcript e (por padrão) queima a legenda no vídeo.
# Uso: subtitles.sh <video> <transcript.json> <saida.mp4> [--srt-only] [--force] [--style padrao|destaque|discreto]
# O .srt fica ao lado da saída (mesmo nome, extensão .srt). Sem fala reconhecida, o vídeo é copiado sem legenda.
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; srt_only=0; style_name=padrao; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --srt-only) srt_only=1; shift ;;
    --style) [ $# -ge 2 ] || die "--style exige um nome (padrao, destaque ou discreto)"; style_name="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
case "$style_name" in
  padrao) style="FontName=Arial,FontSize=14,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2,Alignment=2,MarginV=60" ;;
  destaque) style="FontName=Arial,FontSize=18,Bold=1,PrimaryColour=&H0000FFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=3,Alignment=2,MarginV=80" ;;
  discreto) style="FontName=Arial,FontSize=11,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=1,Alignment=2,MarginV=40" ;;
  *) die "estilo de legenda desconhecido: $style_name (use padrao, destaque ou discreto)" ;;
esac
[ $# -ge 3 ] || die "uso: subtitles.sh <video> <transcript.json> <saida.mp4> [--srt-only] [--force]"
video="$(abspath "$1")"; transcript="$(abspath "$2")"; out="$(abspath "$3")"

need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
[ -f "$transcript" ] || die "transcript não encontrado: $transcript"
duration="$(probe_duration "$video")"

srt="${out%.*}.srt"
if [ "$srt_only" -eq 1 ]; then refuse_existing "$srt" "$force"; else refuse_existing "$out" "$force"; fi

work="$(tmpdir)"
tmp="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -rf "$work" "$tmp"' EXIT
python3 "$here/transcript_to_srt.py" "$transcript" "$duration" > "$work/sub.srt" || die "falha ao gerar o SRT"
# Cópia só para queimar: chaves escapadas (o libass trataria {texto} como código de estilo e o texto sumiria).
# O .srt entregue ao usuário (sub.srt) fica com o texto original.
# A quebra de linha da cópia de queima segue a largura do estilo na tela (o libass quebra de novo o que não cabe).
largura="$(python3 "$here/caption_styles.py" largura "$style_name")"
python3 "$here/transcript_to_srt.py" "$transcript" "$duration" --escapar-ass --largura "$largura" > "$work/burn.srt" || die "falha ao gerar o SRT de queima"

if ! grep -q -e '-->' "$work/sub.srt"; then
  echo "aviso: nenhuma fala reconhecida; o vídeo segue sem legenda" >&2
  [ "$srt_only" -eq 1 ] && exit 0
  cp "$video" "$tmp" && mv -f "$tmp" "$out"
  exit 0
fi
if [ "$srt_only" -eq 1 ]; then
  mv -f "$work/sub.srt" "$srt"
  exit 0
fi

# O filtro `subtitles` exige escapes frágeis para caminhos; rodamos numa pasta
# temporária com nome simples (sub.srt) para evitar problemas com espaços, ':' e aspas.
# Todos os caminhos usados dentro dela são absolutos.
(cd "$work" && ffmpeg -v error -y -i "$video" -vf "subtitles=burn.srt:force_style='${style}'" \
  -c:v libx264 -pix_fmt yuv420p -c:a copy "$tmp") || die "falha ao queimar a legenda"
mv -f "$tmp" "$out"
cp "$work/sub.srt" "$srt"
