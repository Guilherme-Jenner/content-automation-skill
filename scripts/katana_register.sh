#!/usr/bin/env bash
# Registra o RESULTADO de uma variante feita pelo Katana (o agente rodou o fluxo no Higgsfield e baixou o vídeo).
# Uso: katana_register.sh <variants-plan> <id> <video-baixado> <diretorio-de-saida> --budget <orcamento.json> --gasto <creditos> [--job-ids a,b] [--force]
#   - confere que é um vídeo vertical (9:16) com pelo menos 1 s, antes de registrar qualquer gasto;
#   - entrega final-<id>.mp4 de forma atômica, mais final-<id>.katana.json (jobs, gasto, origem) ao lado;
#   - registra o gasto efetivo no orçamento (budget.py externo). Gasto acima do teto é REGISTRADO e o script sai com erro
#     (o arquivo pago é mantido): nada novo deve ser gerado sem decisão do usuário.
# O Katana cobra por conta própria, então não existe cotação prévia a confirmar; o gasto vem do que o Higgsfield informou.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 4 ] || die "uso: katana_register.sh <variants-plan> <id> <video-baixado> <diretorio> --budget <orcamento.json> --gasto <creditos> [--job-ids a,b] [--force]"
plan="$(abspath "$1")"; vid="$2"; video="$(abspath "$3")"; outdir="$(abspath "$4")"; shift 4
budget=""; gasto=""; jobs=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --budget) [ $# -ge 2 ] || die "--budget exige o arquivo de orçamento"; budget="$(abspath "$2")"; shift 2 ;;
    --gasto) [ $# -ge 2 ] || die "--gasto exige o total de créditos que o Higgsfield informou"; gasto="$2"; shift 2 ;;
    --job-ids) [ $# -ge 2 ] || die "--job-ids exige a lista separada por vírgulas"; jobs="$2"; shift 2 ;;
    --force) force=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -n "$budget" ] || die "informe --budget <orcamento.json>"
[ -n "$gasto" ] || die "informe --gasto <creditos> (o valor que o Higgsfield cobrou)"
[ -f "$plan" ] || die "variants-plan não encontrado: $plan"
[ -f "$video" ] || die "vídeo não encontrado: $video"
[ -f "$budget" ] || die "orçamento não encontrado: $budget"
need_cmd ffprobe "brew install ffmpeg"
need_cmd python3 "brew install python"
case "$vid" in
  *[!A-Za-z0-9_-]*|"") die "id de variante inválido: '$vid'" ;;
esac
python3 "$here/validate_variants.py" "$plan" || die "variants-plan inválido: $plan"
python3 "$here/variant_info.py" "$plan" get "$vid" >/dev/null || die "a variante '$vid' não existe no plano"

out="$outdir/final-$vid.mp4"
info_out="$outdir/final-$vid.katana.json"
refuse_existing "$out" "$force"

probe_duration "$video" >/dev/null
dims="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$video" </dev/null)" || die "não foi possível ler o vídeo: $video"
python3 -c "
import sys
w, h = (int(x) for x in sys.argv[1].split(','))
sys.exit(0 if h * 9 >= w * 16 * 0.97 else 1)" "$dims" 2>/dev/null \
  || die "o vídeo do Katana não é vertical 9:16 ($dims): peça ao Katana a saída 9:16 antes de registrar"
dur="$(probe_duration "$video")"
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 1.0 else 1)" "$dur" || die "o vídeo tem menos de 1 s: $video"

mkdir -p "$outdir"
tmp="$outdir/.final-$vid.partial.mp4"
CURRENT_TMP="$tmp"
trap 'rm -f "$CURRENT_TMP"' EXIT
cp "$video" "$tmp"
chave="$(python3 "$here/variant_info.py" "$plan" key "$vid")"
item="katana-$vid-${chave##*-}"
# O crédito já foi consumido: o arquivo é entregue ANTES do registro, e o estouro não o apaga.
mv -f "$tmp" "$out"
CURRENT_TMP=""
python3 - "$info_out" "$vid" "$gasto" "$jobs" "$video" <<'PY'
import json, sys
caminho, vid, gasto, jobs, origem = sys.argv[1:6]
dados = {"variante": vid, "gasto": gasto, "job_ids": [j for j in jobs.split(",") if j], "origem": origem, "editor": "katana"}
with open(caminho, "wb") as f:
    f.write((json.dumps(dados, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
PY
rc=0
python3 "$here/budget.py" externo "$budget" "$item" "$gasto" || rc=$?
if [ "$rc" -eq 3 ]; then
  echo "erro: o gasto passou do teto. O vídeo foi mantido em $out; não gere mais nada sem uma decisão do usuário." >&2
  exit 1
fi
[ "$rc" -eq 0 ] || exit "$rc"
echo "registrado: $out (gasto $gasto)"
