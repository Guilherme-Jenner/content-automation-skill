#!/usr/bin/env bash
# Porta de editor: roda as variantes aprovadas com o editor escolhido no variants-plan.json.
#   local  -> edit-recorded.sh (ffmpeg), custo zero, nunca toca no orçamento.
#   katana -> consome crédito: exige --budget (budget.py), cotação, confirmação do total e gasto dentro do teto.
#             O adaptador real ainda não existe; com CLO_KATANA=fake usa o Katana falso (testes).
# Uso: run-variants.sh <video> <diretorio> --variants <plano> --stage quote|run [--budget <arquivo>] [--force]
#   quote: cota cada variante aprovada e mostra o total. NÃO gera nada e NÃO gasta nada.
#   run:   gera. Para o Katana, só roda variantes cuja cotação foi confirmada (budget.py confirm).
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: run-variants.sh <video> <diretorio> --variants <plano> --stage quote|run [--budget <arquivo>] [--force]"
video="$(abspath "$1")"; work="$(abspath "$2")"; shift 2
plan=""; stage=""; budget=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --variants) [ $# -ge 2 ] || die "--variants exige o variants-plan.json"; plan="$(abspath "$2")"; shift 2 ;;
    --stage) [ $# -ge 2 ] || die "--stage exige quote ou run"; stage="$2"; shift 2 ;;
    --budget) [ $# -ge 2 ] || die "--budget exige o arquivo de orçamento"; budget="$(abspath "$2")"; shift 2 ;;
    --force) force=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -f "$video" ] || die "arquivo não encontrado: $video"
[ -f "$plan" ] || die "variants-plan não encontrado: $plan"
case "$stage" in quote|run) ;; *) die "estágio inválido: '$stage' (use quote ou run)" ;; esac
python3 "$here/validate_variants.py" "$plan" || die "variants-plan inválido: $plan"

editor="$(python3 "$here/variant_info.py" "$plan" editor)"
fflag=""; [ "$force" -eq 1 ] && fflag="--force"

if [ "$editor" = local ]; then
  if [ "$stage" = quote ]; then
    echo "Editor local: custo zero; nenhum crédito será usado."
    exit 0
  fi
  exec "$here/edit-recorded.sh" "$video" "$work" --stage apply --variants "$plan" $fflag
fi

# --- katana ---------------------------------------------------------------------------------
[ "${CLO_KATANA:-}" = fake ] || die "o editor 'katana' ainda não implementado (o adaptador real depende de validar com a conta); use o editor local"
[ -n "$budget" ] || die "o editor katana consome crédito: informe o teto com --budget <arquivo> (crie com: budget.py init <arquivo> <teto>)"
[ -f "$budget" ] || die "orçamento não encontrado: $budget (crie com budget.py init <arquivo> <teto>)"
nl=$'\n'
ids=""
while read -r id ok; do
  if [ "$ok" = sim ]; then ids="${ids}${ids:+$nl}${id}"; fi
done <<EOV
$(python3 "$here/variant_info.py" "$plan" list)
EOV
[ -n "$ids" ] || die "nenhuma variante aprovada; aprove ao menos uma (aprovada: true)"

if [ "$stage" = quote ]; then
  while IFS= read -r id; do
    custo="$("$here/editors/katana_fake.sh" quote "$plan" "$id")"
    python3 "$here/budget.py" quote "$budget" "var-$id" "$custo" >/dev/null
  done <<EOA
$ids
EOA
  python3 "$here/budget.py" status "$budget"
  echo "Nenhum crédito foi gasto. Mostre o total ao usuário; só depois da aprovação rode: budget.py confirm $budget"
  exit 0
fi

# stage run: nada começa antes de TODAS as checagens
mkdir -p "$work"
while IFS= read -r id; do
  refuse_existing "$work/final-$id.mp4" "$force"
  python3 "$here/budget.py" check "$budget" "var-$id" >/dev/null \
    || die "variante $id sem cotação confirmada; rode quote e peça a confirmação do total (budget.py confirm)"
done <<EOA
$ids
EOA

run_one() { # id
  local id="$1" tmp custo
  tmp="$work/.final-$id.partial.mp4"
  # Variável global: o trap roda quando o subshell sai, depois que o escopo local da função acabou.
  CURRENT_TMP="$tmp"
  trap 'rm -f "$CURRENT_TMP"' EXIT
  custo="$("$here/editors/katana_fake.sh" run "$plan" "$id" "$tmp")"
  python3 "$here/budget.py" spend "$budget" "var-$id" "$custo"
  mv -f "$tmp" "$work/final-$id.mp4"
}
concluidas=""; falharam=""
while IFS= read -r id; do
  set +e
  ( set -e; run_one "$id" ) </dev/null
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then concluidas="$concluidas $id"; else falharam="$falharam $id"; fi
done <<EOA
$ids
EOA
echo "Concluídas:${concluidas}"
if [ -n "$falharam" ]; then
  echo "Falharam:${falharam}" >&2
  exit 1
fi
