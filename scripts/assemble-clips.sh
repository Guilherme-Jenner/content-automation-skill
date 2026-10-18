#!/usr/bin/env bash
# Junta os clipes gerados, na ORDEM DO PLANO, em um vídeo 1080x1920 (9:16).
# Uso: assemble-clips.sh <gen-plan> <clips-manifest.json> <saida.mp4> [--force]
#   - falha se faltar clipe de alguma cena, se o arquivo sumiu ou se o hash não bate com o manifesto;
#   - se todos os clipes têm áudio, o áudio é normalizado (~-14 LUFS); se nenhum tem, a saída é muda;
#     clipes com e sem áudio misturados são recusados (decida antes: gerar tudo com áudio ou tudo sem);
#   - a saída é gravada de forma atômica.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; args=()
for a in "$@"; do if [ "$a" = "--force" ]; then force=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 3 ] || die "uso: assemble-clips.sh <gen-plan> <clips-manifest.json> <saida.mp4> [--force]"
plan="$(abspath "$1")"; manifest="$(abspath "$2")"; out="$(abspath "$3")"
[ -f "$plan" ] || die "gen-plan não encontrado: $plan"
[ -f "$manifest" ] || die "manifesto não encontrado: $manifest"
need_cmd ffmpeg "brew install ffmpeg"
need_cmd ffprobe "brew install ffmpeg"
python3 "$here/validate_genplan.py" "$plan" || die "plano de geração inválido: $plan"
refuse_existing "$out" "$force"

lista="$(python3 "$here/clips_manifest.py" verify "$manifest" "$plan")" || die "não é possível montar: os clipes não conferem com o manifesto"

inputs=(); n=0; com_audio=0
while IFS= read -r clip; do
  [ -n "$clip" ] || continue
  inputs+=(-i "$clip")
  if [ -n "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$clip" </dev/null)" ]; then com_audio=$((com_audio + 1)); fi
  n=$((n + 1))
done <<EOL
$lista
EOL
[ "$n" -ge 1 ] || die "nenhum clipe para montar"
if [ "$com_audio" -ne 0 ] && [ "$com_audio" -ne "$n" ]; then
  die "$com_audio de $n clipes têm áudio: não misture clipes com e sem áudio (gere todos com ou todos sem)"
fi

filtro=""; rotulos=""; i=0
while [ "$i" -lt "$n" ]; do
  filtro="${filtro}[${i}:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,fps=25[v${i}];"
  if [ "$com_audio" -gt 0 ]; then
    filtro="${filtro}[${i}:a]aresample=48000,aformat=channel_layouts=stereo[a${i}];"
    rotulos="${rotulos}[v${i}][a${i}]"
  else
    rotulos="${rotulos}[v${i}]"
  fi
  i=$((i + 1))
done
if [ "$com_audio" -gt 0 ]; then
  filtro="${filtro}${rotulos}concat=n=${n}:v=1:a=1[v][a]"; mapas=(-map "[v]" -map "[a]" -c:a aac)
else
  filtro="${filtro}${rotulos}concat=n=${n}:v=1:a=0[v]"; mapas=(-map "[v]" -an)
fi

work="$(tmpdir)"
CURRENT_WORK="$work"
CURRENT_TMP="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -rf "$CURRENT_WORK" "$CURRENT_TMP"' EXIT
ffmpeg -v error -y "${inputs[@]}" -filter_complex "$filtro" "${mapas[@]}" -c:v libx264 -pix_fmt yuv420p "$work/junto.mp4" </dev/null \
  || die "falha ao juntar os clipes"
if [ "$com_audio" -gt 0 ]; then
  "$here/normalize-audio.sh" "$work/junto.mp4" "$CURRENT_TMP" --force || die "falha ao normalizar o áudio"
else
  cp "$work/junto.mp4" "$CURRENT_TMP"
fi
mv -f "$CURRENT_TMP" "$out"
echo "montado: $out"
