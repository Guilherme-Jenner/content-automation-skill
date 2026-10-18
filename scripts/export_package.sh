#!/usr/bin/env bash
# Monta o pacote (vídeo, legenda, horário e passo a passo) para agendar manualmente no Instagram/TikTok.
# Uso: export_package.sh <plano> <post-id> <saida-dir> [--force] [--now <ISO>]
# Não publica nem agenda nada; é o plano B enquanto não houver um agendador (MCP) validado.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

[ $# -ge 3 ] || die "uso: export_package.sh <plano> <post-id> <saida-dir> [--force] [--now <ISO>]"
need_cmd python3 "brew install python"
exec python3 "$here/export_package.py" "$@"
