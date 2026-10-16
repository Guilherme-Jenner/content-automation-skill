#!/usr/bin/env bash
# Edição do vídeo gravado em dois estágios, com aprovação humana no meio.
# Uso: edit-recorded.sh <video> <diretorio_de_trabalho> --stage propose|apply [--force]
#   propose: transcreve e propõe cortes de silêncio -> transcript.json + cut-plan.json (approved=false)
#   apply:   exige cut-plan.json aprovado; corta -> normaliza áudio -> 9:16 -> legenda -> final.mp4 + final.srt
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 4 ] || die "uso: edit-recorded.sh <video> <diretorio> --stage propose|apply [--force]"
video="$1"; work="$2"; stage=""; force=""
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) stage="${2:?}"; shift 2 ;;
    --force) force="--force"; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -f "$video" ] || die "arquivo não encontrado: $video"
mkdir -p "$work"

case "$stage" in
  propose)
    "$here/transcribe.sh" "$video" "$work/transcript.json"
    "$here/silence-detect.sh" "$video" "$work/cut-plan.json"
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
    [ -f "$work/cut-plan.json" ] && [ -f "$work/transcript.json" ] || die "rode antes o estágio propose neste diretório"
    if [ -e "$work/final.mp4" ] && [ -z "$force" ]; then
      die "a saída já existe: $work/final.mp4 (use --force para sobrescrever)"
    fi
    steps="$work/.etapas"
    rm -rf "$steps"; mkdir -p "$steps"
    trap 'rm -rf "$steps"' EXIT
    "$here/apply-cuts.sh" "$video" "$work/cut-plan.json" "$steps/1-cortado.mp4"
    python3 "$here/retime_transcript.py" "$work/transcript.json" "$work/cut-plan.json" > "$steps/transcript.json"
    "$here/normalize-audio.sh" "$steps/1-cortado.mp4" "$steps/2-audio.mp4"
    "$here/reframe-9x16.sh" "$steps/2-audio.mp4" "$steps/3-vertical.mp4"
    "$here/subtitles.sh" "$steps/3-vertical.mp4" "$steps/transcript.json" "$work/final.mp4"
    echo "Pronto: $work/final.mp4 e $work/final.srt"
    ;;
  *) die "estágio inválido: '$stage' (use propose ou apply)" ;;
esac
