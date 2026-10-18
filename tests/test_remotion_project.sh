#!/usr/bin/env bash
# Projeto Remotion (legenda animada palavra a palavra) e scripts/render-remotion.sh. Nenhum teste baixa pacote nem renderiza:
# o render real precisa do Node e das dependências (npm install) e é validado à mão (docs/testes-manuais.md).

_rr() { bash "$ROOT/scripts/render-remotion.sh" "$@"; }

# _input <dir> → transcript fake convertido em remotion-input.json e um vídeo curto
_input() {
  ffmpeg -v error -y -f lavfi -i "color=c=black:size=1080x1920:rate=30:duration=3" -an -c:v libx264 -pix_fmt yuv420p "$1/v.mp4" </dev/null
  python3 "$ROOT/scripts/to_remotion_input.py" "$ROOT/tests/data/transcript_fake.json" "$1/v.mp4" > "$1/in.json"
}

test_project_files_exist_and_are_consistent() {
  local p="$ROOT/remotion"
  assert_file_exists "$p/package.json"; assert_file_exists "$p/src/index.ts"; assert_file_exists "$p/src/Root.tsx"
  assert_file_exists "$p/src/CaptionedVideo.tsx"; assert_file_exists "$p/tsconfig.json"
  python3 - "$p/package.json" <<'PY' || _fail "package.json inválido ou sem as dependências do Remotion"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["private"] is True
for dep in ("remotion", "@remotion/cli", "react", "react-dom"):
    assert dep in d["dependencies"], dep
assert "render" in d["scripts"]
PY
  local s; s=$(cat "$p/src/CaptionedVideo.tsx")
  assert_contains "$s" "padrao" "estilo padrao"; assert_contains "$s" "destaque" "estilo destaque"; assert_contains "$s" "discreto" "estilo discreto"
  assert_contains "$s" "OffthreadVideo" "usa o vídeo de entrada"
  assert_contains "$s" "inicio_s" "usa os tempos das palavras do contrato"
  assert_contains "$(cat "$p/src/Root.tsx")" "CaptionedVideo" "composição registrada"
}

test_check_only_validates_the_input_contract() {
  local d out; d="$(mktemp -d)"; _input "$d"
  out=$(_rr "$d/in.json" "$d/v.mp4" "$d/out.mp4" --check-only 2>&1) || _fail "entrada válida recusada: $out"
  assert_contains "$out" "palavras" "resume as palavras"
  [ ! -e "$d/out.mp4" ] || _fail "--check-only não deve produzir saída"
  printf '%s' '{"video":"x"}' > "$d/ruim.json"
  out=$(_rr "$d/ruim.json" "$d/v.mp4" "$d/out.mp4" --check-only 2>&1) && _fail "contrato inválido aceito"
  assert_contains "$out" "remotion-input" "cita o contrato"
  rm -rf "$d"
}

test_refuses_missing_video_existing_output_and_unsupported_style() {
  local d out; d="$(mktemp -d)"; _input "$d"
  out=$(_rr "$d/in.json" "$d/nao.mp4" "$d/out.mp4" --check-only 2>&1) && _fail "vídeo inexistente aceito"; assert_contains "$out" "não encontrado" "mensagem"
  printf 'x' > "$d/out.mp4"
  out=$(_rr "$d/in.json" "$d/v.mp4" "$d/out.mp4" --check-only 2>&1) && _fail "saída existente aceita"; assert_contains "$out" "--force" "pede --force"
  python3 - "$d/in.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); d["estilo"] = "neon"
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_rr "$d/in.json" "$d/v.mp4" "$d/novo.mp4" --check-only 2>&1) && _fail "estilo desconhecido aceito"; assert_contains "$out" "estilo" "mensagem"
  rm -rf "$d"
}

test_missing_node_gives_an_install_hint() {
  local d out; d="$(mktemp -d)"; _input "$d"
  out=$(PATH="$(dirname "$(command -v python3)")" /bin/bash "$ROOT/scripts/render-remotion.sh" "$d/in.json" "$d/v.mp4" "$d/out.mp4" 2>&1) && _fail "sem Node deveria falhar"
  assert_contains "$out" "brew install node" "dica de instalação no Mac"
  rm -rf "$d"
}

test_missing_dependencies_give_a_clear_message() {
  local d out; d="$(mktemp -d)"; _input "$d"
  [ ! -d "$ROOT/remotion/node_modules" ] || return 0   # já instalado nesta máquina: o caminho de erro não se aplica
  command -v node >/dev/null 2>&1 || return 0
  out=$(_rr "$d/in.json" "$d/v.mp4" "$d/out.mp4" 2>&1) && _fail "sem npm install deveria falhar"
  assert_contains "$out" "npm install" "orienta a instalar as dependências"
  rm -rf "$d"
}

test_remotion_is_documented_with_its_license_note() {
  local s; s=$(cat "$ROOT/remotion/README.md")
  assert_contains "$s" "licença" "fala da licença do Remotion"
  assert_contains "$s" "npm install" "como instalar"
  assert_contains "$s" "render-remotion.sh" "como renderizar"
}
