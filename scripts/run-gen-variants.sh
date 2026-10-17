#!/usr/bin/env bash
# Vários vídeos finais (variantes) a partir dos MESMOS clipes já gerados. Custo zero: nunca toca no orçamento.
# Uso: run-gen-variants.sh <gen-plan> <clips-manifest.json> <diretorio-de-saida> --variants <gen-variants-plan.json> [--force]
#   - roda só as variantes com aprovada: true; cada uma vira final-<id>.mp4 (+ final-<id>.srt) em <diretorio-de-saida>;
#   - cada variante é montada com as cenas escolhidas, na ordem escolhida (assemble-clips.sh) e editada com as
#     próprias legendas e trilha (edit-generated.sh);
#   - TUDO é validado antes de produzir qualquer arquivo (plano, clipes contra o manifesto, legendas, música, saídas
#     existentes); depois, uma variante que falha não impede as outras, e o script termina com erro listando-as;
#   - a música é arquivo do usuário (licença é responsabilidade dele); caminho relativo vale a partir da pasta do plano.
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 3 ] || die "uso: run-gen-variants.sh <gen-plan> <clips-manifest.json> <diretorio-de-saida> --variants <plano> [--force]"
genplan="$(abspath "$1")"; manifest="$(abspath "$2")"; outdir="$(abspath "$3")"; shift 3
plan=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --variants) [ $# -ge 2 ] || die "--variants exige o gen-variants-plan.json"; plan="$(abspath "$2")"; shift 2 ;;
    --force) force=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -n "$plan" ] || die "informe --variants <gen-variants-plan.json>"
[ -f "$genplan" ] || die "gen-plan não encontrado: $genplan"
[ -f "$manifest" ] || die "manifesto não encontrado: $manifest"
[ -f "$plan" ] || die "plano de variantes não encontrado: $plan"
need_cmd ffmpeg "brew install ffmpeg"
need_cmd ffprobe "brew install ffmpeg"
need_cmd python3 "brew install python"

python3 "$here/validate_genplan.py" "$genplan" || die "plano de geração inválido: $genplan"
python3 "$here/validate_gen_variants.py" "$plan" "$genplan" || die "plano de variantes inválido: $plan"

nl=$'\n'
ids=""
while read -r id ok; do
  if [ "$ok" = sim ]; then ids="${ids}${ids:+$nl}${id}"; fi
done <<EOV
$(python3 "$here/gen_variant_info.py" "$plan" list)
EOV
[ -n "$ids" ] || die "nenhuma variante aprovada; aprove ao menos uma (aprovada: true)"

work="$(tmpdir)"
CURRENT_WORK="$work"
trap 'rm -rf "$CURRENT_WORK"' EXIT

fflag=""; [ "$force" -eq 1 ] && fflag="--force"

# 1) validação completa de todas as variantes aprovadas, sem produzir nada
primeiro_clipe=""
while IFS= read -r id; do
  mkdir -p "$work/$id"
  python3 "$here/gen_variant_info.py" "$plan" genplan "$genplan" "$id" > "$work/$id/gen-plan.json"
  python3 "$here/gen_variant_info.py" "$plan" captions "$id" > "$work/$id/captions.json"
  refuse_existing "$outdir/final-$id.mp4" "$force"
  refuse_existing "$outdir/final-$id.srt" "$force"
  lista="$(python3 "$here/clips_manifest.py" verify "$manifest" "$work/$id/gen-plan.json")" \
    || die "variante $id: os clipes não conferem com o manifesto e o plano; gere/registre de novo"
  [ -n "$primeiro_clipe" ] || primeiro_clipe="$(printf '%s\n' "$lista" | head -1)"
  python3 "$here/captions_to_transcript.py" "$work/$id/captions.json" "$work/$id/gen-plan.json" "$manifest" > /dev/null \
    || die "variante $id: as legendas não conferem com as cenas e os clipes; nada foi gerado"
  musica="$(python3 "$here/gen_variant_info.py" "$plan" music "$id")"
  if [ "$musica" != "-" ]; then
    "$here/add-soundtrack.sh" "$primeiro_clipe" "${musica% *}" "$work/$id/validacao.mp4" --volume-db "${musica##* }" --check-only \
      || die "variante $id: a música não pode ser usada; nada foi gerado"
  fi
done <<EOA
$ids
EOA

# 2) produção: uma variante que falha não impede as outras
mkdir -p "$outdir"
feitas=""; falharam=""
produzir() { # id
  local id="$1" musica extra
  extra=()
  musica="$(python3 "$here/gen_variant_info.py" "$plan" music "$id")"
  if [ "$musica" != "-" ]; then extra=(--music "${musica% *}" --volume-db "${musica##* }"); fi
  "$here/assemble-clips.sh" "$work/$id/gen-plan.json" "$manifest" "$work/$id/montado.mp4" --force
  "$here/edit-generated.sh" "$work/$id/montado.mp4" "$work/$id/gen-plan.json" "$manifest" "$outdir/final-$id.mp4" \
    --captions "$work/$id/captions.json" ${extra[@]+"${extra[@]}"} $fflag
}
while IFS= read -r id; do
  set +e
  ( set -e; produzir "$id" ) </dev/null
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then feitas="$feitas $id"; else falharam="$falharam $id"; fi
done <<EOA
$ids
EOA
echo "Concluídas:${feitas}"
if [ -n "$falharam" ]; then
  echo "Falharam:${falharam}" >&2
  exit 1
fi
