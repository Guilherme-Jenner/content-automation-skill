#!/usr/bin/env bash
# Gerador de clipes FALSO para testes: cota um custo fictício e cria um clipe de exemplo. Não usa rede nem crédito.
# Uso:
#   fake.sh quote <gen-plan.json> <id>                 -> imprime a cotação (créditos fictícios)
#   fake.sh run   <gen-plan.json> <id> <saida.mp4>     -> cria o clipe e imprime o custo efetivo
# Custo fictício por segundo: 480p=1, 720p=2, 1080p=4; +20% com áudio.
# CLO_GEN_FAKE_OVERRUN=<id> dobra o custo efetivo dessa cena (somente testes).
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

[ $# -ge 3 ] || die "uso: fake.sh quote|run <gen-plan.json> <id> [saida.mp4]"
modo="$1"; plano="$2"; id="$3"
[[ "$id" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || die "id de cena inválido: '$id'"
info="$(python3 "$here/../genplan_info.py" "$plano" get "$id")" || die "a cena '$id' não existe no plano"
read -r duracao resolucao audio _aspecto <<EOI
$info
EOI

fator=1
case "$resolucao" in 480p) fator=1 ;; 720p) fator=2 ;; 1080p) fator=4 ;; *) die "resolução desconhecida: $resolucao" ;; esac
custo="$(python3 -c "import sys; d, f, a = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3] == 'sim'; print(f'{d * f * (1.2 if a else 1):g}')" "$duracao" "$fator" "$audio")"

case "$modo" in
  quote) printf '%s\n' "$custo" ;;
  run)
    [ $# -ge 4 ] || die "uso: fake.sh run <gen-plan.json> <id> <saida.mp4>"
    need_cmd ffmpeg "brew install ffmpeg"
    case "$resolucao" in 480p) tam=480x854 ;; 720p) tam=720x1280 ;; *) tam=1080x1920 ;; esac
    if [ "$audio" = sim ]; then
      ffmpeg -v error -y -f lavfi -i "testsrc2=size=${tam}:rate=25:duration=${duracao}" -f lavfi -i "sine=frequency=330:duration=${duracao}" \
        -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$4" </dev/null || die "falha ao criar o clipe de exemplo"
    else
      ffmpeg -v error -y -f lavfi -i "testsrc2=size=${tam}:rate=25:duration=${duracao}" \
        -c:v libx264 -pix_fmt yuv420p -an "$4" </dev/null || die "falha ao criar o clipe de exemplo"
    fi
    if [ "${CLO_GEN_FAKE_OVERRUN:-}" = "$id" ]; then
      python3 -c "import sys; print(f'{float(sys.argv[1]) * 2:g}')" "$custo"
    else
      printf '%s\n' "$custo"
    fi
    ;;
  *) die "modo inválido: $modo" ;;
esac
