#!/usr/bin/env bash
# Agendador FALSO para testes: finge agendar e devolve um id externo. Nunca usa rede nem conta real.
# Uso: fake.sh <snapshot-dir>   -> imprime o id externo
# O agendador só aceita um SNAPSHOT APROVADO (pasta criada por `schedule_log.py reserve`): ele confere que o
# vídeo da pasta ainda tem o hash aprovado. Adaptadores reais devem fazer a mesma conferência.
# CLO_FAKE_SCHEDULER_FAIL=1 simula uma falha do agendador (somente testes).
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

[ $# -eq 1 ] || die "uso: fake.sh <snapshot-dir>"
python3 "$here/verify_snapshot.py" "$1" || die "o agendador só aceita um snapshot aprovado (pasta gerada por schedule_log.py reserve): $1"
[ "${CLO_FAKE_SCHEDULER_FAIL:-}" != 1 ] || die "falha simulada do agendador (teste)"
printf 'fake-%s\n' "$(python3 -c "import hashlib,sys,time; print(hashlib.sha1((sys.argv[1]+str(time.time_ns())).encode()).hexdigest()[:8])" "$1")"
