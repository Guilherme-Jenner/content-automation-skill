#!/usr/bin/env bash
# Monta os carrosséis (e, opcionalmente, o vídeo) das variantes APROVADAS de um slideshow-plan.json.
# Uso: make-slideshow.sh <slideshow-plan.json> <diretorio de saida> [--formato carrossel|video|ambos] [--aspecto 9:16|3:4|4:5] [--only <id>] [--force]
#   --formato carrossel (padrão): só as páginas JPEG (o TikTok recusa PNG), para postar como carrossel do Instagram / Modo Foto do TikTok
#   --formato video: só o vídeo; ambos: os dois
#   --aspecto 9:16 (padrão, 1080x1920: TikTok e Reels), 3:4 (1080x1440: o TikTok mostra o Modo Foto numa caixa de cerca de 3:4, então a foto fica centralizada em vez de cortada no topo) ou 4:5 (1080x1350: carrossel do feed do Instagram)
# Por variante aprovada gera:
#   carrossel-<id>/slide-NN.jpg   uma página por slide, já com o texto, na ordem de postagem
#   slideshow-<id>.mp4 e .srt     (formato video/ambos) cada foto na duração do slide, legenda queimada, trilha opcional
# Não gasta crédito: tudo local (ffmpeg). As fotos nunca são modificadas. Variantes não aprovadas são puladas.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; only=""; formato=carrossel; aspecto=9:16; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --formato) [ $# -ge 2 ] || die "--formato exige carrossel, video ou ambos"; formato="$2"; shift 2 ;;
    --aspecto) [ $# -ge 2 ] || die "--aspecto exige 9:16, 3:4 ou 4:5"; aspecto="$2"; shift 2 ;;
    --only) [ $# -ge 2 ] || die "--only exige o id de uma variante"; only="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || die "uso: make-slideshow.sh <slideshow-plan.json> <diretorio de saida> [--formato carrossel|video|ambos] [--aspecto 9:16|4:5] [--only <id>] [--force]"
plan="$(abspath "$1")"; outdir="$(abspath "$2")"
case "$formato" in carrossel|video|ambos) ;; *) die "formato inválido: $formato (use carrossel, video ou ambos)" ;; esac
case "$aspecto" in 9:16) W=1080; H=1920 ;; 4:5) W=1080; H=1350 ;; 3:4) W=1080; H=1440 ;; *) die "aspecto inválido: $aspecto (use 9:16, 3:4 ou 4:5)" ;; esac

need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$plan" ] || die "plano não encontrado: $plan"
python3 "$here/validate_slideshow.py" "$plan" || die "o plano é inválido (corrija e rode de novo)"
mkdir -p "$outdir"
style="$(python3 "$here/slideshow_info.py" estilo "$plan")"

ids="$(python3 "$here/slideshow_info.py" aprovadas "$plan")"
[ -n "$ids" ] || die "nenhuma variante aprovada no plano (aprovada: true) — nada a montar"

FILTRO='[0:v]split[a][b];[a]scale=W:H:force_original_aspect_ratio=increase,crop=W:H,boxblur=20:5[bg];[b]scale=W:H:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[v]'

monta() { # id
  local id="$1" work out tmp n=0 foto dur papel t=0 mid pngs
  out="$outdir/slideshow-$id.mp4"
  [ "$formato" = carrossel ] || refuse_existing "$out" "$force"
  [ "$formato" = video ] || { [ ! -d "$outdir/carrossel-$id" ] || [ "$force" -eq 1 ] || die "a saída já existe: $outdir/carrossel-$id (use --force para sobrescrever)"; }
  work="$(tmpdir)"
  trap 'rm -rf "$work"' RETURN
  : > "$work/lista.txt"
  while IFS=$'\t' read -r foto dur papel; do
    n=$((n + 1))
    ffmpeg -v error -y -loop 1 -framerate 30 -t "$dur" -i "$foto" -filter_complex "${FILTRO//W:H/$W:$H}" -map "[v]" \
      -c:v libx264 -r 30 -pix_fmt yuv420p "$work/seg$n.mp4" </dev/null || { echo "falha ao ler a foto: $foto" >&2; return 1; }
    printf "file 'seg%s.mp4'\n" "$n" >> "$work/lista.txt"
  done < <(python3 "$here/slideshow_info.py" slides "$plan" "$id")
  ffmpeg -v error -y -f concat -safe 0 -i "$work/lista.txt" -c copy "$work/mudo.mp4" </dev/null || return 1
  python3 "$here/slideshow_info.py" transcript "$plan" "$id" > "$work/transcript.json" || return 1
  bash "$here/subtitles.sh" "$work/mudo.mp4" "$work/transcript.json" "$work/legendado.mp4" --style "$style" || return 1

  # páginas do carrossel: um quadro no meio de cada slide (o texto já está queimado)
  n=0
  [ "$formato" = video ] || { rm -rf "$outdir/carrossel-$id"; mkdir -p "$outdir/carrossel-$id"; }
  [ "$formato" = video ] || while IFS=$'\t' read -r foto dur papel; do
    n=$((n + 1))
    mid="$(python3 -c "import sys; print(float(sys.argv[1]) + float(sys.argv[2]) / 2)" "$t" "$dur")"
    t="$(python3 -c "import sys; print(float(sys.argv[1]) + float(sys.argv[2]))" "$t" "$dur")"
    ffmpeg -v error -y -ss "$mid" -i "$work/legendado.mp4" -frames:v 1 -q:v 2 "$outdir/carrossel-$id/$(printf 'slide-%02d.jpg' "$n")" </dev/null || return 1
  done < <(python3 "$here/slideshow_info.py" slides "$plan" "$id")

  [ "$formato" != carrossel ] || return 0
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
