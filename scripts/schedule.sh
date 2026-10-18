#!/usr/bin/env bash
# Agenda um post aprovado. Por padrão apenas SIMULA (não grava nada).
# Uso: schedule.sh <plano> <post-id> --approvals <dir> --scheduler fake [--confirm] [--now <ISO>, só em testes]
#   - o log fica SEMPRE ao lado do plano (<pasta do plano>/.schedule-log.json): não há opção para trocá-lo,
#     senão o mesmo post poderia ser agendado de novo por outro log;
#   - o post precisa ter aprovação válida; a verificação é refeita sob a trava na hora de reservar, e o
#     agendador recebe um snapshot do vídeo e do conteúdo aprovados (não o plano vivo);
#   - --confirm agenda de verdade; só use depois que o usuário confirmar de novo, em linguagem clara;
#   - o mesmo post (mesmo vídeo e conteúdo) nunca é agendado duas vezes; mudar um post já agendado exige
#     cancelar o anterior no agendador e rodar `schedule_log.py supersede` (ver a skill schedule-post).
# Agendadores reais (MCP) ainda não estão implementados: só existe o `fake`.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: schedule.sh <plano> <post-id> --approvals <dir> --scheduler fake [--confirm]"
plan="$(abspath "$1")"; post="$2"; shift 2
approvals=""; scheduler=""; confirm=0; now=""
while [ $# -gt 0 ]; do
  case "$1" in
    --approvals) [ $# -ge 2 ] || die "--approvals exige um diretório"; approvals="$(abspath "$2")"; shift 2 ;;
    --scheduler) [ $# -ge 2 ] || die "--scheduler exige um nome (por enquanto: fake)"; scheduler="$2"; shift 2 ;;
    --now) [ $# -ge 2 ] || die "--now exige uma data ISO"; now="$2"; shift 2 ;;
    --confirm) confirm=1; shift ;;
    *) die "opção desconhecida: $1 (o log de agendamentos tem local fixo ao lado do plano, não há --log)" ;;
  esac
done
[ -f "$plan" ] || die "plano não encontrado: $plan"
[ -n "$approvals" ] || die "--approvals é obrigatório"
[ -n "$scheduler" ] || die "--scheduler é obrigatório (por enquanto: fake)"
case "$scheduler" in
  fake) ;;
  *) die "o agendador '$scheduler' ainda não implementado (só existe o fake); use o pacote manual: export_package.sh" ;;
esac
need_cmd python3 "brew install python"
log="$(dirname "$plan")/.schedule-log.json"

# 1) plano válido; o prazo (≥ 15 min e ≤ 30 dias) vale para ESTE post
if [ -n "$now" ]; then
  python3 "$here/validate_schedule.py" "$plan" --post "$post" --now "$now" || die "plano inválido; nada foi agendado"
else
  python3 "$here/validate_schedule.py" "$plan" --post "$post" || die "plano inválido; nada foi agendado"
fi
# 2) aprovação válida para o conteúdo exato (refeita sob a trava no reserve)
python3 "$here/approval.py" verify "$plan" "$post" "$approvals" || die "o post '$post' não tem aprovação válida; nada foi agendado"
# 3) ainda não agendado
estado="$(python3 "$here/schedule_log.py" status "$plan" "$post" "$log")"
case "$estado" in
  livre) ;;
  em_andamento) die "o post '$post' está com uma reserva em_andamento (outro processo, ou um que caiu). Antes de liberar, conferir no agendador se o post foi criado; só então: schedule_log.py release <plano> $post <log> --conferido" ;;
  conflito) die "o post '$post' já agendado com outro conteúdo. Cancele o anterior no agendador e registre a substituição: schedule_log.py supersede $log $post" ;;
  *) die "o post '$post' já agendado (estado: $estado); não será agendado de novo" ;;
esac

if [ "$confirm" -eq 0 ]; then
  python3 "$here/schedule_log.py" describe "$plan" "$post"
  echo "SIMULAÇÃO: nada foi agendado. Para agendar de verdade rode de novo com --confirm (só depois do 'aprovo' do usuário)."
  exit 0
fi

# Reserva (verifica a aprovação de novo, sob a trava) e recebe o snapshot aprovado.
rc=0
saida="$(python3 "$here/schedule_log.py" reserve "$plan" "$post" "$log" "$scheduler" "$approvals")" || rc=$?
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$saida"
  exit "$rc"
fi
snapshot="$(printf '%s\n' "$saida" | tail -1)"

if ! externo="$("$here/schedulers/$scheduler.sh" "$snapshot")"; then
  python3 "$here/schedule_log.py" release "$plan" "$post" "$log" --conferido >/dev/null
  die "o agendador '$scheduler' falhou; a reserva foi liberada e nada ficou agendado"
fi
case "$externo" in
  ""|*$'\n'*) die "o agendador devolveu um id inválido; a reserva continua em_andamento: conferir no agendador antes de liberar" ;;
esac
if ! python3 "$here/schedule_log.py" commit "$plan" "$post" "$log" "$externo"; then
  echo "ATENÇÃO: agendado no agendador (id externo: $externo), mas NÃO registrado no log. Registre com: schedule_log.py commit <plano> $post <log> $externo. Não tente agendar de novo antes." >&2
  exit 1
fi
