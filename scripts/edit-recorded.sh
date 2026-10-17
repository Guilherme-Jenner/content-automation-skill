#!/usr/bin/env bash
# Edição do vídeo gravado em dois estágios, com aprovação humana no meio.
# Uso: edit-recorded.sh <video> <diretorio_de_trabalho> --stage propose|apply [--force]
#   propose: transcreve e propõe cortes de silêncio -> transcript.json + cut-plan.json (approved=false)
#   apply:   exige cut-plan.json aprovado; corta -> normaliza áudio -> 9:16 -> legenda -> final.mp4 + final.srt
# Ajustes no plano: edite cut-plan.json; rodar propose de novo exige --force (e apaga o plano aprovado).
# Variantes: apply --variants <variants-plan.json> gera final-<id>.mp4 para cada variante APROVADA (editor local).
# CLO_TEST_FAIL_VARIANT=<id> simula falha numa variante (somente testes).
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 4 ] || die "uso: edit-recorded.sh <video> <diretorio> --stage propose|apply [--force]"
video="$(abspath "$1")"; work="$(abspath "$2")"; stage=""; force=0; variants=""
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) [ $# -ge 2 ] || die "--stage exige propose ou apply"; stage="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --variants) [ $# -ge 2 ] || die "--variants exige o variants-plan.json"; variants="$(abspath "$2")"; shift 2 ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -f "$video" ] || die "arquivo não encontrado: $video"
fflag=""; [ "$force" -eq 1 ] && fflag="--force"

apply_variants() {
  [ -f "$variants" ] || die "variants-plan não encontrado: $variants"
  [ -f "$work/transcript.json" ] || die "rode antes o estágio propose neste diretório (falta transcript.json)"
  python3 "$here/validate_variants.py" "$variants" || die "variants-plan inválido: $variants"
  python3 - "$variants" "$video" <<'PY' || die "o variants-plan foi feito para outro vídeo"
import json, os, sys
norm = lambda p: os.path.normcase(os.path.normpath(os.path.abspath(p)))
plano = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if norm(plano["bruto"]) == norm(sys.argv[2]) else 1)
PY
  local editor ids aprovadas puladas id
  editor="$(python3 "$here/variant_info.py" "$variants" editor)"
  [ "$editor" = "local" ] || die "o editor '$editor' ainda não implementado; use editor local no variants-plan"
  aprovadas=""; puladas=""
  ids="$(python3 "$here/variant_info.py" "$variants" list)"
  while read -r id ok; do
    if [ "$ok" = sim ]; then aprovadas="$aprovadas $id"; else puladas="$puladas $id"; fi
  done <<EOV
$ids
EOV
  [ -n "$aprovadas" ] || die "nenhuma variante aprovada; aprove ao menos uma (aprovada: true) no variants-plan"
  for id in $aprovadas; do refuse_existing "$work/final-$id.mp4" "$force"; done

  local concluidas="" falharam=""
  for id in $aprovadas; do
    if ( run_variant "$id" ); then concluidas="$concluidas $id"; else falharam="$falharam $id"; fi
  done
  [ -z "$puladas" ] || echo "Puladas (variante não aprovada):${puladas}"
  echo "Concluídas:${concluidas}"
  if [ -n "$falharam" ]; then
    echo "Falharam:${falharam}" >&2
    return 1
  fi
}

run_variant() { # id
  local id="$1" vdir="$work/v$1" info minsil margem estilo
  # Aspas duplas: $vdir é local da função e precisa ser expandido agora, não quando o subshell sair.
  # shellcheck disable=SC2064
  trap "rm -f \"$vdir\"/*.mp4" EXIT
  [ "${CLO_TEST_FAIL_VARIANT:-}" != "$id" ] || die "falha simulada na variante $id (teste)"
  mkdir -p "$vdir"
  info="$(python3 "$here/variant_info.py" "$variants" get "$id")"
  read -r minsil margem estilo <<EOI
$info
EOI
  "$here/silence-detect.sh" "$video" "$vdir/silence.json" --min-silence "$minsil" --pad "$margem" --force
  python3 "$here/variant_to_cutplan.py" "$variants" "$id" "$video" --merge "$vdir/silence.json" > "$vdir/cut-plan.json"
  "$here/apply-cuts.sh" "$video" "$vdir/cut-plan.json" "$vdir/1-cortado.mp4" --force
  python3 "$here/retime_transcript.py" "$work/transcript.json" "$vdir/cut-plan.json" > "$vdir/transcript.json"
  "$here/normalize-audio.sh" "$vdir/1-cortado.mp4" "$vdir/2-audio.mp4" --force
  "$here/reframe-9x16.sh" "$vdir/2-audio.mp4" "$vdir/3-vertical.mp4" --force
  "$here/subtitles.sh" "$vdir/3-vertical.mp4" "$vdir/transcript.json" "$work/final-$id.mp4" --force --style "$estilo"
}

case "$stage" in
  propose)
    # Valida o vídeo antes de qualquer trabalho ou arquivo de saída.
    probe_duration "$video" >/dev/null
    require_min_duration "$video"
    require_audio "$video"
    refuse_existing "$work/transcript.json" "$force"
    refuse_existing "$work/cut-plan.json" "$force"
    mkdir -p "$work"
    "$here/transcribe.sh" "$video" "$work/transcript.json" $fflag
    "$here/silence-detect.sh" "$video" "$work/cut-plan.json" $fflag
    python3 - "$work/cut-plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
total = sum(c["fim_s"] - c["inicio_s"] for c in p["cortes"])
print(f"Plano proposto (AINDA NÃO APROVADO): {len(p['cortes'])} corte(s), {total:.1f}s removidos de {p['duracao_s']:.1f}s.")
for i, c in enumerate(p["cortes"], 1):
    print(f"  {i}. {c['inicio_s']:.2f}s -> {c['fim_s']:.2f}s ({c['motivo']})")
print("Revise com o usuário e só então marque approved=true em cut-plan.json.")
PY
    ;;
  apply)
    if [ -n "$variants" ]; then
      apply_variants
      exit $?
    fi
    [ -f "$work/cut-plan.json" ] && [ -f "$work/transcript.json" ] || die "rode antes o estágio propose neste diretório"
    # Compara em Python: no Windows/Git Bash o argumento chega convertido (C:/...), então a comparação textual falharia.
    python3 - "$work/cut-plan.json" "$video" <<'PY' || die "o plano em $work foi feito para outro vídeo; rode o propose para este vídeo"
import json, os, sys
norm = lambda p: os.path.normcase(os.path.normpath(os.path.abspath(p)))
plano = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if norm(plano["video"]) == norm(sys.argv[2]) else 1)
PY
    refuse_existing "$work/final.mp4" "$force"
    steps="$work/.etapas"
    rm -rf "$steps"; mkdir -p "$steps"
    trap 'rm -rf "$steps"' EXIT
    "$here/apply-cuts.sh" "$video" "$work/cut-plan.json" "$steps/1-cortado.mp4"
    python3 "$here/retime_transcript.py" "$work/transcript.json" "$work/cut-plan.json" > "$steps/transcript.json"
    "$here/normalize-audio.sh" "$steps/1-cortado.mp4" "$steps/2-audio.mp4"
    "$here/reframe-9x16.sh" "$steps/2-audio.mp4" "$steps/3-vertical.mp4"
    "$here/subtitles.sh" "$steps/3-vertical.mp4" "$steps/transcript.json" "$work/final.mp4" --force
    echo "Pronto: $work/final.mp4 e $work/final.srt"
    ;;
  *) die "estágio inválido: '$stage' (use propose ou apply)" ;;
esac
