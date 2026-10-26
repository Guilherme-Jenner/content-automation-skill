#!/usr/bin/env bash
# Monta os slideshows (vídeo 9:16 + páginas PNG do carrossel) das variantes APROVADAS de um slideshow-plan.json.
# Uso: make-slideshow.sh <slideshow-plan.json> <diretorio de saida> [--only <id>] [--force]
# Por variante aprovada gera:
#   slideshow-<id>.mp4   vídeo 1080x1920, cada foto na duração do slide, legenda (texto do slide) queimada, trilha opcional
#   slideshow-<id>.srt   legendas
#   carrossel-<id>/slide-NN.png   uma página por slide, já com o texto, para postar como carrossel
# Não gasta crédito: tudo local (ffmpeg). As fotos nunca são modificadas. Variantes não aprovadas são puladas.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; only=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --only) [ $# -ge 2 ] || die "--only exige o id de uma variante"; only="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || die "uso: make-slideshow.sh <slideshow-plan.json> <diretorio de saida> [--only <id>] [--force]"
plan="$(abspath "$1")"; outdir="$(abspath "$2")"

need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$plan" ] || die "plano não encontrado: $plan"
python3 "$here/validate_slideshow.py" "$plan" || die "o plano é inválido (corrija e rode de novo)"
mkdir -p "$outdir"
style="$(python3 "$here/slideshow_info.py" estilo "$plan")"

ids="$(python3 "$here/slideshow_info.py" aprovadas "$plan")"
[ -n "$ids" ] || die "nenhuma variante aprovada no plano (aprovada: true) — nada a montar"

FILTRO='[0:v]split[a][b];[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:5[bg];[b]scale=1080:1920:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[v]'

monta() { # id
  local id="$1" work out tmp n=0 foto dur papel t=0 mid pngs
  out="$outdir/slideshow-$id.mp4"
  refuse_existing "$out" "$force"
  work="$(tmpdir)"
  trap 'rm -rf "$work"' RETURN
  : > "$work/lista.txt"
  while IFS=$'\t' read -r foto dur papel; do
    n=$((n + 1))
    ffmpeg -v error -y -loop 1 -framerate 30 -t "$dur" -i "$foto" -filter_complex "$FILTRO" -map "[v]" \
      -c:v libx264 -r 30 -pix_fmt yuv420p "$work/seg$n.mp4" </dev/null || { echo "falha ao ler a foto: $foto" >&2; return 1; }
    printf "file 'seg%s.mp4'\n" "$n" >> "$work/lista.txt"
  done < <(python3 "$here/slideshow_info.py" slides "$plan" "$id")
  ffmpeg -v error -y -f concat -safe 0 -i "$work/lista.txt" -c copy "$work/mudo.mp4" </dev/null || return 1
  python3 "$here/slideshow_info.py" transcript "$plan" "$id" > "$work/transcript.json" || return 1
  bash "$here/subtitles.sh" "$work/mudo.mp4" "$work/transcript.json" "$work/legendado.mp4" --style "$style" || return 1

  # páginas do carrossel: um quadro no meio de cada slide (o texto já está queimado)
  rm -rf "$outdir/carrossel-$id"; mkdir -p "$outdir/carrossel-$id"
  n=0
  while IFS=$'\t' read -r foto dur papel; do
    n=$((n + 1))
    mid="$(python3 -c "import sys; print(float(sys.argv[1]) + float(sys.argv[2]) / 2)" "$t" "$dur")"
    t="$(python3 -c "import sys; print(float(sys.argv[1]) + float(sys.argv[2]))" "$t" "$dur")"
    ffmpeg -v error -y -ss "$mid" -i "$work/legendado.mp4" -frames:v 1 "$outdir/carrossel-$id/$(printf 'slide-%02d.png' "$n")" </dev/null || return 1
  done < <(python3 "$here/slideshow_info.py" slides "$plan" "$id")

  tmp="$(python3 "$here/slideshow_info.py" musica "$plan" "$id")"
  if [ -n "$tmp" ]; then
    local music="${tmp%%$'\t'*}" vol="${tmp#*$'\t'}" extra=()
    [ -z "$vol" ] || extra=(--volume-db "$vol")
    bash "$here/add-soundtrack.sh" "$work/legendado.mp4" "$music" "$out" ${extra[@]+"${extra[@]}"} --force || return 1
  else
    cp "$work/legendado.mp4" "$out"
  fi
  cp "$work/legendado.srt" "$(srt_path "$out")"
}

feitas=(); falhas=(); puladas=()
if [ -n "$only" ]; then
  printf '%s\n' "$ids" | grep -qxF -- "$only" || die "a variante '$only' não existe ou não está aprovada"
fi
while IFS= read -r id; do
  [ -z "$only" ] || [ "$id" = "$only" ] || { puladas+=("$id"); continue; }
  if ( monta "$id" ); then feitas+=("$id"); else falhas+=("$id"); fi
done <<< "$ids"

echo "concluídas: ${feitas[*]:-nenhuma}"
[ ${#puladas[@]} -eq 0 ] || echo "puladas: ${puladas[*]}"
[ ${#falhas[@]} -eq 0 ] || { echo "falhas: ${falhas[*]}" >&2; exit 1; }
