#!/usr/bin/env bash
# Gera os clipes das cenas de um gen-plan.json sob o teto de créditos (budget.py).
#
# Gerador `fake` (testes):
#   generate-clips.sh <gen-plan> <diretorio> --budget <arq> --stage quote|run --generator fake [--force]
#   quote: cota cada cena e mostra o total. NÃO gera nada e NÃO gasta nada.
#   run:   gera. Só roda cenas com cotação confirmada (budget.py confirm <arquivo> <total>), recota (grátis) e
#          recusa se o preço subiu, pula cenas já pagas que têm arquivo (nunca cobra duas vezes) e INTERROMPE o
#          lote no primeiro estouro de cotação (o gasto efetivo fica registrado).
#
# Gerador `mcp-agent` (real): o script NÃO chama o Higgsfield; quem chama é o AGENTE (skill), com o payload exato:
#   --stage payload --scene <id> --cost-only            imprime o payload de generate_video com get_cost:true
#   --stage register-quote --scene <id> --custo <n> --budget <arq>   registra a cotação que o agente obteve
#   (o usuário aprova o TOTAL → budget.py confirm <arq> <total>)
#   --stage payload --scene <id> --budget <arq>         payload de geração (get_cost:false); só com cotação confirmada
#   --stage register --scene <id> --job-id <uuid> --custo <n> --arquivo <caminho> --budget <arq> [--force]
#                                                       confere o clipe baixado, gasta (estouro é registrado) e atualiza o manifesto
#
# Saída: <diretorio>/clips/<id>.mp4 e <diretorio>/clips-manifest.json.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: generate-clips.sh <gen-plan> <diretorio> --stage <estágio> --generator fake|mcp-agent [--budget <arquivo>] [--force]"
plan="$(abspath "$1")"; work="$(abspath "$2")"; shift 2
budget=""; stage=""; generator=""; force=0; scene=""; jobid=""; custo_arg=""; arquivo=""; cost_only=0; reemitir=0
while [ $# -gt 0 ]; do
  case "$1" in
    --budget) [ $# -ge 2 ] || die "--budget exige o arquivo de orçamento"; budget="$(abspath "$2")"; shift 2 ;;
    --stage) [ $# -ge 2 ] || die "--stage exige um estágio"; stage="$2"; shift 2 ;;
    --generator) [ $# -ge 2 ] || die "--generator exige um nome (fake ou mcp-agent)"; generator="$2"; shift 2 ;;
    --scene) [ $# -ge 2 ] || die "--scene exige o id da cena"; scene="$2"; shift 2 ;;
    --job-id) [ $# -ge 2 ] || die "--job-id exige o id do job"; jobid="$2"; shift 2 ;;
    --custo) [ $# -ge 2 ] || die "--custo exige um número"; custo_arg="$2"; shift 2 ;;
    --arquivo) [ $# -ge 2 ] || die "--arquivo exige o caminho do clipe baixado"; arquivo="$(abspath "$2")"; shift 2 ;;
    --cost-only) cost_only=1; shift ;;
    --reemitir) reemitir=1; shift ;;
    --force) force=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -f "$plan" ] || die "gen-plan não encontrado: $plan"
case "$generator" in
  fake|mcp-agent) ;;
  "") die "informe o gerador com --generator (fake ou mcp-agent)" ;;
  *) die "gerador desconhecido: '$generator' (use fake ou mcp-agent)" ;;
esac
case "$generator:$stage" in
  fake:quote|fake:run|mcp-agent:payload|mcp-agent:register-quote|mcp-agent:register) ;;
  mcp-agent:quote|mcp-agent:run) die "no modo mcp-agent o agente chama o Higgsfield: use os estágios payload, register-quote e register" ;;
  *) die "estágio '$stage' inválido para o gerador '$generator'" ;;
esac
python3 "$here/validate_genplan.py" "$plan" || die "plano de geração inválido: $plan"

item_of() { python3 "$here/genplan_info.py" "$plan" key "$1"; }
state_of() { python3 "$here/budget.py" state "$budget" "$1"; }
need_budget() {
  [ -n "$budget" ] || die "o gerador consome crédito: informe o teto com --budget <arquivo> (crie com: budget.py init <arquivo> <teto>)"
  [ -f "$budget" ] || die "orçamento não encontrado: $budget (crie com budget.py init <arquivo> <teto>)"
}
nl=$'\n'

# ===== gerador mcp-agent ======================================================================
if [ "$generator" = mcp-agent ]; then
  [ -n "$scene" ] || die "informe a cena com --scene <id>"
  item="$(item_of "$scene")" || die "a cena '$scene' não existe no plano"
  case "$stage" in
    payload)
      if [ "$cost_only" -eq 1 ]; then
        exec python3 "$here/genpayload.py" "$plan" "$scene" --cost-only
      fi
      need_budget
      python3 "$here/budget.py" check "$budget" "$item" >/dev/null \
        || die "cena $scene não pode ser gerada agora: $(python3 "$here/budget.py" check "$budget" "$item" 2>&1 | sed 's/^recusado: //')"
      # O payload de geração sai UMA vez por cena: um segundo envio poderia criar (e cobrar) um segundo job.
      emitflag=""; [ "$reemitir" -eq 0 ] || emitflag="--reemitir"
      saida="$(python3 "$here/budget.py" emit "$budget" "$item" $emitflag 2>&1)" || die "${saida#recusado: }"
      exec python3 "$here/genpayload.py" "$plan" "$scene"
      ;;
    register-quote)
      need_budget
      [ -n "$custo_arg" ] || die "informe a cotação obtida com get_cost em --custo <n>"
      python3 "$here/budget.py" quote "$budget" "$item" "$custo_arg"
      python3 "$here/budget.py" status "$budget"
      echo "Nenhum crédito foi gasto. Quando todas as cenas estiverem cotadas, mostre o 'total cotado' ao usuário; só depois da aprovação rode: budget.py confirm $budget <total cotado>"
      exit 0
      ;;
    register)
      need_budget
      [[ "$jobid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || die "--job-id deve ser o UUID do job devolvido pelo Higgsfield"
      [ -n "$custo_arg" ] || die "informe o custo efetivo em --custo <n> (obtenha pela diferença de balance antes/depois ou por transactions)"
      python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > 0 else 1)" "$custo_arg" 2>/dev/null \
        || die "o custo efetivo deve ser um número maior que zero (recebido '$custo_arg'); confira com balance/transactions"
      [ -f "$arquivo" ] || die "arquivo do clipe não encontrado: informe --arquivo <caminho do clipe baixado>"
      dur_real="$(probe_duration "$arquivo")"
      [ -n "$(ffprobe -v error -select_streams v -show_entries stream=codec_type -of csv=p=0 "$arquivo" 2>/dev/null)" ] || die "o arquivo não tem faixa de vídeo: $arquivo"
      read -r pedida resolucao _audio _aspecto <<EOI
$(python3 "$here/genplan_info.py" "$plan" get "$scene")
EOI
      python3 -c "import sys; sys.exit(0 if abs(float(sys.argv[1]) - float(sys.argv[2])) <= 1.0 else 1)" "$dur_real" "$pedida" \
        || die "a duração do clipe ($dur_real s) difere da pedida ($pedida s) em mais de 1 s; não será registrado"
      IFS=, read -r larg alt <<EOI
$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$arquivo")
EOI
      case "$resolucao" in 480p) alt_min=854 ;; 720p) alt_min=1280 ;; *) alt_min=1920 ;; esac
      python3 -c "import sys; w, h, m = map(float, sys.argv[1:4]); sys.exit(0 if abs(w / h - 0.5625) <= 0.03 and h >= 0.9 * m else 1)" "$larg" "$alt" "$alt_min" \
        || die "a proporção/resolução do clipe (${larg}x${alt}) não corresponde ao plano (9:16, ${resolucao}); não será registrado"
      mkdir -p "$work/clips"
      python3 "$here/clips_manifest.py" check-new "$work/clips-manifest.json" "$scene" "$arquivo" "$jobid" || die "o clipe não pode ser registrado nesta cena"
      # Uma operação por cena de cada vez (check, cópia, gasto e manifesto formam uma unidade).
      CURRENT_LOCK="$work/clips/.$scene.lock"
      mkdir "$CURRENT_LOCK" 2>/dev/null || die "há outra operação registrando a cena $scene (ou uma anterior caiu): se tiver certeza de que nenhuma está rodando, apague $CURRENT_LOCK"
      CURRENT_TMP=""
      trap 'rm -rf "$CURRENT_LOCK"; [ -z "$CURRENT_TMP" ] || rm -f "$CURRENT_TMP"' EXIT
      python3 "$here/budget.py" check "$budget" "$item" --ignorar-teto --exigir-emitido >/dev/null \
        || die "cena $scene não pode ser registrada: $(python3 "$here/budget.py" check "$budget" "$item" --ignorar-teto --exigir-emitido 2>&1 | sed 's/^recusado: //')"
      refuse_existing "$work/clips/$scene.mp4" "$force"
      CURRENT_TMP="$(mktemp "$work/clips/.$scene.XXXXXX")"
      cp "$arquivo" "$CURRENT_TMP"
      rc=0
      python3 "$here/budget.py" spend "$budget" "$item" "$custo_arg" || rc=$?
      if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then exit "$rc"; fi
      tmp="$CURRENT_TMP"; CURRENT_TMP=""   # o crédito foi consumido: o clipe é preservado
      mv -f "$tmp" "$work/clips/$scene.mp4" || die "não foi possível mover o clipe pago; ele está em $tmp"
      python3 "$here/clips_manifest.py" add "$work/clips-manifest.json" "$scene" "clips/$scene.mp4" "$custo_arg" "$item" mcp-agent "$jobid" \
        || die "clipe pago e salvo em clips/$scene.mp4, mas NÃO registrado no manifesto"
      if [ "$rc" -eq 3 ]; then
        echo "Estouro da cotação na cena $scene: o gasto efetivo foi registrado; interrompa o lote e fale com o usuário." >&2
        exit 3
      fi
      echo "registrado: cena $scene (job $jobid, custo $custo_arg)"
      exit 0
      ;;
  esac
fi

# ===== gerador fake ===========================================================================
need_budget
gen="$here/generators/$generator.sh"
ids="$(python3 "$here/genplan_info.py" "$plan" list)"

if [ "$stage" = quote ]; then
  while IFS= read -r id; do
    item="$(item_of "$id")"
    case "$(state_of "$item")" in
      confirmado|emitido|gasto) echo "já cotada e confirmada: cena $id"; continue ;;
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
