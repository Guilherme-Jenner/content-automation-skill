#!/usr/bin/env bash
# Gera o .srt a partir do transcript e (por padrão) queima a legenda no vídeo.
# Uso: subtitles.sh <video> <transcript.json> <saida.mp4> [--srt-only] [--force] [--style padrao|destaque|discreto]
# O .srt fica ao lado da saída (mesmo nome, extensão .srt). Sem fala reconhecida, o vídeo é copiado sem legenda.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; srt_only=0; style_name=padrao; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --srt-only) srt_only=1; shift ;;
    --style) [ $# -ge 2 ] || die "--style exige um nome (padrao, destaque, discreto ou tiktok)"; style_name="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
case "$style_name" in
  padrao) style="FontName=Arial,FontSize=14,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=2,Alignment=2,MarginV=60" ;;
  destaque) style="FontName=Arial,FontSize=18,Bold=1,PrimaryColour=&H0000FFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=3,Alignment=2,MarginV=80" ;;
  discreto) style="FontName=Arial,FontSize=11,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=1,Alignment=2,MarginV=40" ;;
  tiktok) style="@tiktok" ;;   # fonte do TikTok (TikTok Sans SemiBold, OFL); calculado pela altura do vídeo mais abaixo
  *) die "estilo de legenda desconhecido: $style_name (use padrao, destaque, discreto ou tiktok)" ;;
esac
[ $# -ge 3 ] || die "uso: subtitles.sh <video> <transcript.json> <saida.mp4> [--style padrao|destaque|discreto|tiktok] [--srt-only] [--force]"
video="$(abspath "$1")"; transcript="$(abspath "$2")"; out="$(abspath "$3")"

need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
[ -f "$transcript" ] || die "transcript não encontrado: $transcript"
duration="$(probe_duration "$video")"

fontsdir_arg=""
if [ "$style_name" = tiktok ]; then
  # TikTok Sans SemiBold, texto branco com contorno preto, centralizado no terço superior (como o texto do Modo Foto).
  # O libass escala tudo pela altura do vídeo (referência 288): tamanho, contorno e margem saem nessa escala.
  altura="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$video" 2>/dev/null)" || altura=""
  case "$altura" in ''|*[!0-9]*) altura=1920 ;; esac
  style="$(python3 -c "import sys; h=int(sys.argv[1]); k=288/h; topo=0.27 if h/1080 > 1.5 else 0.17; print('FontName=TikTok Sans SemiBold,FontSize=%.2f,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BorderStyle=1,Outline=%.2f,Alignment=6,MarginV=%d' % (74*k, 6*k, round(h*topo*k)))" "$altura")"
  fontsdir_arg=":fontsdir=fonts"
fi
srt="$(srt_path "$out")"
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
if [ -n "$fontsdir_arg" ]; then
  mkdir -p "$work/fonts" && cp "$here/../fonts/TikTokSans-SemiBold.ttf" "$work/fonts/" || die "fonte do TikTok não encontrada em fonts/"
fi
(cd "$work" && ffmpeg -v error -y -i "$video" -vf "subtitles=burn.srt${fontsdir_arg}:force_style='${style}'" \
  -c:v libx264 -pix_fmt yuv420p -c:a copy "$tmp") || die "falha ao queimar a legenda"
mv -f "$tmp" "$out"
cp "$work/sub.srt" "$srt"
