#!/usr/bin/env bash
# Renderiza a legenda animada palavra a palavra (Remotion) sobre um vídeo já editado.
# Uso: render-remotion.sh <remotion-input.json> <video> <saida.mp4> [--force] [--check-only]
#   - o JSON segue schemas/remotion-input.schema.json (gerado por to_remotion_input.py); estilos: padrao, destaque, discreto;
#   - --check-only valida o contrato, o vídeo e a saída sem precisar do Node e sem renderizar;
#   - o render usa o projeto em remotion/ (instale uma vez: cd remotion && npm install) e grava de forma atômica.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; check_only=0; args=()
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    --check-only) check_only=1 ;;
    *) args+=("$a") ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 3 ] || die "uso: render-remotion.sh <remotion-input.json> <video> <saida.mp4> [--force] [--check-only]"
input="$(abspath "$1")"; video="$(abspath "$2")"; out="$(abspath "$3")"
project="$here/../remotion"

if [ "$check_only" -eq 0 ]; then
  need_cmd node "brew install node"
  need_cmd npx "brew install node"
fi
need_cmd python3 "brew install python"
[ -f "$input" ] || die "remotion-input não encontrado: $input"
[ -f "$video" ] || die "vídeo não encontrado: $video"
python3 "$here/validate_json.py" "$here/../schemas/remotion-input.schema.json" "$input" || die "o arquivo não segue o contrato remotion-input: $input"
resumo="$(python3 - "$input" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if d["estilo"] not in ("padrao", "destaque", "discreto"):
    print(f"estilo desconhecido: '{d['estilo']}' (use padrao, destaque ou discreto)", file=sys.stderr)
    sys.exit(1)
if not d["palavras"]:
    print("o remotion-input não tem palavras: não há o que animar", file=sys.stderr)
    sys.exit(1)
print(f"{len(d['palavras'])} palavras, estilo {d['estilo']}, {d['largura']}x{d['altura']} a {d['fps']:g} fps")
PY
)" || die "remotion-input inválido: $input (estilo ou palavras)"
refuse_existing "$out" "$force"
if [ "$check_only" -eq 1 ]; then
  echo "ok: $resumo"
  exit 0
fi

need_cmd ffprobe "brew install ffmpeg"
[ -d "$project/node_modules" ] || die "as dependências do Remotion não estão instaladas: rode (cd \"$project\" && npm install)"
dur="$(probe_duration "$video")"

work="$(tmpdir)"
CURRENT_WORK="$work"
CURRENT_TMP="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -rf "$CURRENT_WORK" "$CURRENT_TMP"' EXIT
mkdir -p "$work/public"
cp "$video" "$work/public/entrada.mp4"
python3 - "$input" "$dur" "$work/props.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["video"] = "entrada.mp4"          # o vídeo vai para a pasta public temporária
d["duracao_s"] = float(sys.argv[2])  # medido no vídeo, não no JSON
with open(sys.argv[3], "wb") as f:
    f.write(json.dumps(d, ensure_ascii=False).encode("utf-8"))
PY
echo "renderizando: $resumo"
(cd "$project" && npx remotion render src/index.ts CaptionedVideo "$CURRENT_TMP" --props="$work/props.json" --public-dir="$work/public" --codec=h264) \
  || die "o render do Remotion falhou (veja a mensagem acima)"
[ -s "$CURRENT_TMP" ] || die "o Remotion não gerou o vídeo"
mv -f "$CURRENT_TMP" "$out"
echo "pronto: $out"
