#!/usr/bin/env bash
# Instala as dependências do Remotion (npm install pelo lockfile) em uma pasta ESTÁVEL do usuário.
# Uso: setup-remotion.sh
#   - a pasta é $CLO_REMOTION_HOME (padrão: ~/.cache/clo/remotion), fora do plugin: o plugin instalado pelo marketplace
#     fica num cache com o nome da versão, e um npm install lá dentro se perderia a cada atualização;
#   - roda de novo sem problema (reinstala só se o package-lock.json mudou);
#   - baixa pacotes da internet (Remotion e outras dependências) e, no primeiro render, um Chrome headless.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

project="$here/../remotion"
home="${CLO_REMOTION_HOME:-$HOME/.cache/clo/remotion}"
need_cmd node "brew install node"
need_cmd npm "brew install node"
[ -f "$project/package.json" ] && [ -f "$project/package-lock.json" ] || die "o projeto Remotion do plugin está incompleto (falta package.json ou package-lock.json): $project"

mkdir -p "$home"
if [ -d "$home/node_modules" ] && [ -f "$home/package-lock.json" ] && cmp -s "$project/package-lock.json" "$home/package-lock.json"; then
  echo "dependências do Remotion já instaladas em $home"
  exit 0
fi
cp "$project/package.json" "$project/package-lock.json" "$home/"
echo "instalando as dependências do Remotion em $home (baixa pacotes da internet)..."
(cd "$home" && npm ci --no-audit --no-fund) || die "o npm ci falhou (veja a mensagem acima)"
echo "pronto: dependências em $home"
