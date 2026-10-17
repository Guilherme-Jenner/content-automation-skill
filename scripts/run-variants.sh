#!/usr/bin/env bash
# Porta de editor: roda as variantes aprovadas com o editor escolhido no variants-plan.json.
#   local  -> edit-recorded.sh (ffmpeg), custo zero, nunca toca no orçamento.
#   katana -> consome crédito: exige --budget (budget.py), cotação, confirmação do total e gasto dentro do teto.
#             O adaptador real ainda não existe; com CLO_KATANA=fake usa o Katana falso (testes).
# Uso: run-variants.sh <video> <diretorio> --variants <plano> --stage quote|run [--budget <arquivo>] [--force]
#   quote: cota cada variante aprovada e mostra o total. NÃO gera nada e NÃO gasta nada.
#   run:   gera. Para o Katana, só roda variantes cuja cotação foi confirmada (budget.py confirm <arquivo> <total>).
#          Variantes já pagas e com arquivo final são puladas (nunca se cobra duas vezes); um estouro de
#          cotação é registrado e INTERROMPE o lote.
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

item_of() { python3 "$here/variant_info.py" "$plan" key "$1"; }
state_of() { python3 "$here/budget.py" state "$budget" "$1"; }

if [ "$stage" = quote ]; then
  while IFS= read -r id; do
    item="$(item_of "$id")"
    case "$(state_of "$item")" in
      confirmado|gasto) echo "já cotada e confirmada: variante $id"; continue ;;
    esac
    custo="$("$here/editors/katana_fake.sh" quote "$plan" "$id" </dev/null)"
    python3 "$here/budget.py" quote "$budget" "$item" "$custo" >/dev/null
  done <<EOA
$ids
EOA
  python3 "$here/budget.py" status "$budget"
  echo "Nenhum crédito foi gasto. Mostre o 'total cotado' ao usuário; só depois da aprovação rode: budget.py confirm $budget <total cotado>"
  exit 0
fi

# stage run: nada começa antes de TODAS as checagens
mkdir -p "$work"
todo=""; feitas=""
while IFS= read -r id; do
  item="$(item_of "$id")"
  if [ "$(state_of "$item")" = gasto ] && [ -e "$work/final-$id.mp4" ]; then
    feitas="$feitas $id"   # já paga e entregue: nunca se cobra de novo
    continue
  fi
  refuse_existing "$work/final-$id.mp4" "$force"
  atual="$("$here/editors/katana_fake.sh" quote "$plan" "$id" </dev/null)"
  python3 "$here/budget.py" check "$budget" "$item" "$atual" >/dev/null \
    || die "variante $id sem cotação confirmada (ou preço mudou): $(python3 "$here/budget.py" check "$budget" "$item" "$atual" 2>&1 | sed 's/^recusado: //'). Rode quote e peça a confirmação do total"
  todo="${todo}${todo:+$nl}${id}"
done <<EOA
$ids
EOA
[ -z "$feitas" ] || echo "Puladas (já concluída e paga):${feitas}"

run_one() { # id → 0 ok | 3 estouro registrado (arquivo mantido) | outro = falha
  local id="$1" tmp custo rc
  tmp="$work/.final-$id.partial.mp4"
  # Variável global: o trap roda quando o subshell sai, depois que o escopo local da função acabou.
  CURRENT_TMP="$tmp"
  trap 'rm -f "$CURRENT_TMP"' EXIT
  custo="$("$here/editors/katana_fake.sh" run "$plan" "$id" "$tmp")"
  set +e
  python3 "$here/budget.py" spend "$budget" "$(item_of "$id")" "$custo"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then exit "$rc"; fi
  # O crédito já foi consumido: o arquivo é preservado mesmo se o mv falhar.
  CURRENT_TMP=""
  mv -f "$tmp" "$work/final-$id.mp4" || { echo "erro: não foi possível mover o vídeo pago; ele está em $tmp" >&2; exit 1; }
  exit "$rc"
}

concluidas=""; falharam=""; estouro=""
if [ -n "$todo" ]; then
  while IFS= read -r id; do
    set +e
    ( set -e; run_one "$id" ) </dev/null
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      concluidas="$concluidas $id"
    elif [ "$rc" -eq 3 ]; then
      estouro="$id"
      break
    else
      falharam="$falharam $id"
    fi
  done <<EOA
$todo
EOA
fi
echo "Concluídas:${concluidas}"
if [ -n "$estouro" ]; then
  echo "Estouro da cotação na variante $estouro: o gasto efetivo foi registrado e o lote foi interrompido; as variantes seguintes não foram geradas." >&2
  exit 1
fi
if [ -n "$falharam" ]; then
  echo "Falharam:${falharam}" >&2
  exit 1
fi
