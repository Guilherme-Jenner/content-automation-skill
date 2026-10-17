#!/usr/bin/env bash
# Agendador FALSO para testes: finge agendar e devolve um id externo. Nunca usa rede nem conta real.
# Uso: fake.sh <plano> <post-id>   -> imprime o id externo
# CLO_FAKE_SCHEDULER_FAIL=1 simula uma falha do agendador (somente testes).
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

[ $# -eq 2 ] || die "uso: fake.sh <plano> <post-id>"
[ "${CLO_FAKE_SCHEDULER_FAIL:-}" != 1 ] || die "falha simulada do agendador (teste)"
printf 'fake-%s\n' "$(python3 -c "import hashlib,sys,time; print(hashlib.sha1((sys.argv[1]+sys.argv[2]+str(time.time_ns())).encode()).hexdigest()[:8])" "$1" "$2")"
