#!/usr/bin/env bash
# Agenda um post aprovado. Por padrão apenas SIMULA (não grava nada).
# Uso: schedule.sh <plano> <post-id> --approvals <dir> --log <arquivo.json> --scheduler fake [--confirm] [--now <ISO>]
#   - o plano precisa estar válido (validate_schedule.py) e o post precisa ter aprovação válida (approval.py verify);
#   - --confirm agenda de verdade; só use depois de o usuário confirmar de novo, em linguagem clara;
#   - o mesmo post (mesmo vídeo e conteúdo) nunca é agendado duas vezes (schedule_log.py).
# Agendadores reais (MCP) ainda não estão implementados: só existe o `fake`.
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 2 ] || die "uso: schedule.sh <plano> <post-id> --approvals <dir> --log <arquivo> --scheduler fake [--confirm] [--now <ISO>]"
plan="$(abspath "$1")"; post="$2"; shift 2
approvals=""; log=""; scheduler=""; confirm=0; now=""
while [ $# -gt 0 ]; do
  case "$1" in
    --approvals) [ $# -ge 2 ] || die "--approvals exige um diretório"; approvals="$(abspath "$2")"; shift 2 ;;
    --log) [ $# -ge 2 ] || die "--log exige um arquivo"; log="$(abspath "$2")"; shift 2 ;;
    --scheduler) [ $# -ge 2 ] || die "--scheduler exige um nome (por enquanto: fake)"; scheduler="$2"; shift 2 ;;
    --now) [ $# -ge 2 ] || die "--now exige uma data ISO"; now="$2"; shift 2 ;;
    --confirm) confirm=1; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
[ -f "$plan" ] || die "plano não encontrado: $plan"
[ -n "$approvals" ] || die "--approvals é obrigatório"
[ -n "$log" ] || die "--log é obrigatório"
[ -n "$scheduler" ] || die "--scheduler é obrigatório (por enquanto: fake)"
case "$scheduler" in
  fake) ;;
  *) die "o agendador '$scheduler' ainda não implementado (só existe o fake); use o pacote manual: export_package.sh" ;;
esac
need_cmd python3 "brew install python"

nowflag=""; [ -z "$now" ] || nowflag="--now"
# 1) plano válido (inclui o prazo: ≥ 15 min e ≤ 30 dias a partir de agora)
python3 "$here/validate_schedule.py" "$plan" $nowflag ${now:+"$now"} || die "plano inválido; nada foi agendado"
# 2) aprovação válida para o conteúdo exato
python3 "$here/approval.py" verify "$plan" "$post" "$approvals" || die "o post '$post' não tem aprovação válida; nada foi agendado"
# 3) ainda não agendado
estado="$(python3 "$here/schedule_log.py" status "$plan" "$post" "$log")"
if [ "$estado" != livre ]; then
  die "o post '$post' já agendado (estado: $estado); não será agendado de novo"
fi

if [ "$confirm" -eq 0 ]; then
  python3 "$here/schedule_log.py" describe "$plan" "$post"
  echo "SIMULAÇÃO: nada foi agendado. Para agendar de verdade rode de novo com --confirm (só depois do 'aprovo' do usuário)."
  exit 0
fi

python3 "$here/schedule_log.py" reserve "$plan" "$post" "$log" "$scheduler" >/dev/null || exit $?
if ! externo="$("$here/schedulers/$scheduler.sh" "$plan" "$post")"; then
  python3 "$here/schedule_log.py" release "$plan" "$post" "$log" >/dev/null
  die "o agendador '$scheduler' falhou; a reserva foi liberada e nada ficou agendado"
fi
python3 "$here/schedule_log.py" commit "$plan" "$post" "$log" "$externo"
