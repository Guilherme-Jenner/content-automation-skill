#!/usr/bin/env bash
# Katana FALSO para testes: devolve um vídeo de exemplo e um custo fictício (1,5 crédito por segundo mantido).
# Nunca chama o Higgsfield e nunca gasta crédito de verdade.
# Uso:
#   katana_fake.sh quote <variants-plan.json> <id>                  -> imprime a cotação
#   katana_fake.sh run   <variants-plan.json> <id> <saida.mp4>      -> cria o vídeo e imprime o custo efetivo
# CLO_KATANA_FAKE_OVERRUN=<id> faz o custo efetivo dessa variante ser o dobro da cotação (teste de estouro).
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

[ $# -ge 3 ] || die "uso: katana_fake.sh quote|run <variants-plan.json> <id> [saida.mp4]"
modo="$1"; plano="$2"; id="$3"
segundos="$(python3 "$here/../variant_info.py" "$plano" seconds "$id")"
custo="$(python3 -c "import sys; print(f'{float(sys.argv[1]) * 1.5:g}')" "$segundos")"

case "$modo" in
  quote) printf '%s\n' "$custo" ;;
  run)
    [ $# -ge 4 ] || die "uso: katana_fake.sh run <variants-plan.json> <id> <saida.mp4>"
    need_cmd ffmpeg "brew install ffmpeg"
    ffmpeg -v error -y -f lavfi -i "testsrc=size=1080x1920:rate=25:duration=2" -f lavfi -i "sine=frequency=440:duration=2" \
      -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$4" || die "falha ao gerar o vídeo de exemplo"
    if [ "${CLO_KATANA_FAKE_OVERRUN:-}" = "$id" ]; then
      python3 -c "import sys; print(f'{float(sys.argv[1]) * 2:g}')" "$custo"
    else
      printf '%s\n' "$custo"
    fi
    ;;
  *) die "modo inválido: $modo" ;;
esac
