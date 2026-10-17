#!/usr/bin/env bash
# Gera os clipes das cenas de um gen-plan.json sob o teto de créditos (budget.py).
# Uso: generate-clips.sh <gen-plan> <diretorio> --budget <arquivo> --stage quote|run [--generator fake] [--force]
#   quote: cota cada cena e mostra o total. NÃO gera nada e NÃO gasta nada.
#   run:   gera. Só roda cenas com cotação confirmada (budget.py confirm <arquivo> <total>), recota (grátis) e
#          recusa se o preço subiu, pula cenas já pagas que têm arquivo (nunca cobra duas vezes) e INTERROMPE o
#          lote no primeiro estouro de cotação (o gasto efetivo fica registrado).
# Saída: <diretorio>/clips/<id>.mp4 e <diretorio>/clips-manifest.json.
# Geradores: `fake` (testes). O gerador real é executado pelo agente (modo mcp-agent, Task 4).
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: generate-clips.sh <gen-plan> <diretorio> --budget <arquivo> --stage quote|run [--generator fake] [--force]"
plan="$(abspath "$1")"; work="$(abspath "$2")"; shift 2
budget=""; stage=""; generator=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --budget) [ $# -ge 2 ] || die "--budget exige o arquivo de orçamento"; budget="$(abspath "$2")"; shift 2 ;;
    --stage) [ $# -ge 2 ] || die "--stage exige quote ou run"; stage="$2"; shift 2 ;;
    --generator) [ $# -ge 2 ] || die "--generator exige um nome (fake)"; generator="$2"; shift 2 ;;
    --force) force=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -f "$plan" ] || die "gen-plan não encontrado: $plan"
[ -n "$budget" ] || die "o gerador consome crédito: informe o teto com --budget <arquivo> (crie com: budget.py init <arquivo> <teto>)"
[ -f "$budget" ] || die "orçamento não encontrado: $budget (crie com budget.py init <arquivo> <teto>)"
case "$stage" in quote|run) ;; *) die "estágio inválido: '$stage' (use quote ou run)" ;; esac
case "$generator" in
  fake) ;;
  "") die "informe o gerador com --generator (por enquanto: fake)" ;;
  *) die "o gerador '$generator' ainda não implementado nesta etapa (só existe o fake)" ;;
esac
python3 "$here/validate_genplan.py" "$plan" || die "plano de geração inválido: $plan"

gen="$here/generators/$generator.sh"
item_of() { python3 "$here/genplan_info.py" "$plan" key "$1"; }
state_of() { python3 "$here/budget.py" state "$budget" "$1"; }
nl=$'\n'
ids="$(python3 "$here/genplan_info.py" "$plan" list)"

if [ "$stage" = quote ]; then
  while IFS= read -r id; do
    item="$(item_of "$id")"
    case "$(state_of "$item")" in
      confirmado|gasto) echo "já cotada e confirmada: cena $id"; continue ;;
    esac
    custo="$("$gen" quote "$plan" "$id" </dev/null)"
    python3 "$here/budget.py" quote "$budget" "$item" "$custo" >/dev/null
  done <<EOA
$ids
EOA
  python3 "$here/budget.py" status "$budget"
  echo "Nenhum crédito foi gasto. Mostre o 'total cotado' ao usuário; só depois da aprovação rode: budget.py confirm $budget <total cotado>"
  exit 0
fi

# stage run -----------------------------------------------------------------------------------
mkdir -p "$work/clips"
# Uma execução por vez no mesmo diretório (senão duas execuções gerariam a mesma cena).
CURRENT_LOCK="$work/.run.lock"
mkdir "$CURRENT_LOCK" 2>/dev/null || die "há outra execução em andamento neste diretório (ou uma anterior caiu): se tiver certeza de que nenhuma está rodando, apague $CURRENT_LOCK"
CURRENT_TMP=""
trap 'rm -rf "$CURRENT_LOCK"' EXIT

todo=""; feitas=""
while IFS= read -r id; do
  item="$(item_of "$id")"
  if [ "$(state_of "$item")" = gasto ] && [ -e "$work/clips/$id.mp4" ]; then
    feitas="$feitas $id"   # já paga e entregue: nunca se cobra de novo
    continue
  fi
  refuse_existing "$work/clips/$id.mp4" "$force"
  atual="$("$gen" quote "$plan" "$id" </dev/null)"
  python3 "$here/budget.py" check "$budget" "$item" "$atual" >/dev/null \
    || die "cena $id sem cotação confirmada (ou preço mudou): $(python3 "$here/budget.py" check "$budget" "$item" "$atual" 2>&1 | sed 's/^recusado: //'). Rode quote e peça a confirmação do total"
  todo="${todo}${todo:+$nl}${id}"
done <<EOA
$ids
EOA
[ -z "$feitas" ] || echo "Puladas (já concluída e paga):${feitas}"

run_one() { # id → 0 ok | 3 estouro registrado (arquivo mantido) | outro = falha
  local id="$1" tmp custo rc item
  item="$(item_of "$id")"
  tmp="$work/clips/.$id.partial.mp4"
  # Variável global: o trap roda quando o subshell sai, depois que o escopo local da função acabou.
  CURRENT_TMP="$tmp"
  trap 'rm -f "$CURRENT_TMP"' EXIT
  custo="$("$gen" run "$plan" "$id" "$tmp")"
  set +e
  python3 "$here/budget.py" spend "$budget" "$item" "$custo"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then exit "$rc"; fi
  # O crédito já foi consumido: o arquivo é preservado mesmo se o resto falhar.
  CURRENT_TMP=""
  mv -f "$tmp" "$work/clips/$id.mp4" || { echo "erro: não foi possível mover o clipe pago; ele está em $tmp" >&2; exit 1; }
  python3 "$here/clips_manifest.py" add "$work/clips-manifest.json" "$id" "clips/$id.mp4" "$custo" "$item" "$generator" \
    || { echo "erro: clipe pago e salvo em clips/$id.mp4, mas NÃO registrado no manifesto" >&2; exit 1; }
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
  echo "Estouro da cotação na cena $estouro: o gasto efetivo foi registrado e o lote foi interrompido; as cenas seguintes não foram geradas." >&2
  exit 1
fi
if [ -n "$falharam" ]; then
  echo "Falharam:${falharam}" >&2
  exit 1
fi
