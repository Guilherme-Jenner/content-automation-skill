#!/usr/bin/env bash
# Aplica um plano de cortes APROVADO a um vídeo (remove os trechos listados).
# Uso: apply-cuts.sh <video> <cut-plan.json> <saida.mp4> [--force]
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 3 ] || die "uso: apply-cuts.sh <video> <cut-plan.json> <saida.mp4> [--force]"
video="$1"; plan="$2"; out="$3"; force=0
[ "${4:-}" = "--force" ] && force=1

need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"
[ -f "$plan" ] || die "plano de cortes não encontrado: $plan"

python3 "$here/validate_cutplan.py" "$plan" || die "plano de cortes inválido: $plan"
approved="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8'))['approved'])" "$plan")"
[ "$approved" = "True" ] || die "o plano de cortes ainda não foi aprovado (approved=false); peça a aprovação antes de aplicar"
if [ -e "$out" ] && [ "$force" -eq 0 ]; then
  die "a saída já existe: $out (use --force para sobrescrever)"
fi

duration="$(probe_duration "$video")"
require_audio "$video"
plan_duration="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8'))['duracao_s'])" "$plan")"
python3 -c "import sys; sys.exit(0 if abs(float(sys.argv[1])-float(sys.argv[2])) <= 0.1 else 1)" "$plan_duration" "$duration" \
  || die "a duração do plano (${plan_duration}s) não bate com a do vídeo (${duration}s); este plano foi feito para outro vídeo?"

# Trechos a manter = complemento dos cortes.
keep="$(python3 - "$plan" "$duration" <<'PY'
import json, sys
plano = json.load(open(sys.argv[1], encoding="utf-8"))
dur = float(sys.argv[2])
pos = 0.0
trechos = []
for c in sorted(plano["cortes"], key=lambda c: c["inicio_s"]):
    if c["inicio_s"] - pos > 0.05:
        trechos.append((pos, c["inicio_s"]))
    pos = max(pos, c["fim_s"])
if dur - pos > 0.05:
    trechos.append((pos, dur))
if sum(b - a for a, b in trechos) < 1.0:
    print("o resultado ficaria com menos de 1 s depois dos cortes", file=sys.stderr)
    sys.exit(4)
for a, b in trechos:
    print(f"{a:.3f} {b:.3f}")
PY
)" || exit 1
[ -n "$keep" ] || die "os cortes removem o vídeo inteiro"

filter=""; labels=""; n=0
while read -r a b; do
  filter="${filter}[0:v]trim=start=${a}:end=${b},setpts=PTS-STARTPTS[v${n}];[0:a]atrim=start=${a}:end=${b},asetpts=PTS-STARTPTS[a${n}];"
  labels="${labels}[v${n}][a${n}]"
  n=$((n + 1))
done <<EOK
$keep
EOK
filter="${filter}${labels}concat=n=${n}:v=1:a=1[v][a]"

tmp="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -f "$tmp"' EXIT
ffmpeg -v error -y -i "$video" -filter_complex "$filter" -map "[v]" -map "[a]" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac "$tmp" || die "falha ao aplicar os cortes"
mv -f "$tmp" "$out"
trap - EXIT
