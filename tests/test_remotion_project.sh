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
  command -v node >/dev/null 2>&1 || return 0
  out=$(CLO_REMOTION_HOME="$d/vazio" _rr "$d/in.json" "$d/v.mp4" "$d/out.mp4" 2>&1) && _fail "sem as dependências deveria falhar"
  assert_contains "$out" "setup-remotion.sh" "orienta o script de instalação"
  assert_contains "$out" "npm install" "diz o que ele faz"
  rm -rf "$d"
}

# _fakebin <dir> → npm falso (cria node_modules e registra o uso) e npx falso (grava o argumento 5 como o vídeo renderizado)
_fakebin() {
  mkdir -p "$1/bin"
  cat > "$1/bin/npm" <<'EOS'
#!/usr/bin/env bash
echo "npm $*" >> "$FAKE_LOG"
mkdir -p node_modules; : > node_modules/.fake
EOS
  cat > "$1/bin/npx" <<'EOS'
#!/usr/bin/env bash
echo "npx $*" >> "$FAKE_LOG"
echo "cwd=$(pwd)" >> "$FAKE_LOG"
[ -f src/index.ts ] || { echo "sem src/index.ts no diretório de render" >&2; exit 9; }
printf 'video renderizado' > "$5"
EOS
  chmod +x "$1/bin/npm" "$1/bin/npx"
}

test_setup_installs_dependencies_into_a_stable_user_directory() {
  command -v node >/dev/null 2>&1 || return 0
  local d; d="$(mktemp -d)"; _fakebin "$d"
  FAKE_LOG="$d/log" CLO_REMOTION_HOME="$d/home" PATH="$d/bin:$PATH" bash "$ROOT/scripts/setup-remotion.sh" >/dev/null 2>&1 || _fail "setup falhou"
  assert_file_exists "$d/home/package.json"; assert_file_exists "$d/home/package-lock.json"
  assert_contains "$(cat "$d/log")" "npm ci" "instala pelo lockfile"
  assert_file_exists "$d/home/node_modules/.fake"
  rm -rf "$d"
}

test_render_runs_from_the_stable_directory_with_fresh_sources_and_delivers_atomically() {
  command -v node >/dev/null 2>&1 || return 0
  local d out; d="$(mktemp -d)"; _input "$d"; _fakebin "$d"
  FAKE_LOG="$d/log" CLO_REMOTION_HOME="$d/home" PATH="$d/bin:$PATH" bash "$ROOT/scripts/setup-remotion.sh" >/dev/null 2>&1 || _fail "setup falhou"
  mkdir -p "$d/home/src"; printf 'velho' > "$d/home/src/index.ts"   # código antigo de uma versão anterior do plugin
  FAKE_LOG="$d/log" CLO_REMOTION_HOME="$d/home" PATH="$d/bin:$PATH" bash "$ROOT/scripts/render-remotion.sh" "$d/in.json" "$d/v.mp4" "$d/out.mp4" >/dev/null 2>&1 || _fail "render falhou"
  assert_file_exists "$d/out.mp4"
  assert_contains "$(cat "$d/log")" "remotion render src/index.ts CaptionedVideo" "chama o render da composição"
  assert_contains "$(cat "$d/log")" "--props=" "passa as propriedades"
  assert_contains "$(cat "$d/home/src/index.ts")" "registerRoot" "as fontes foram atualizadas a partir do plugin"
  [ -z "$(find "$d" -name '.out.mp4.partial*' | head -1)" ] || _fail "sobrou arquivo parcial"
  rm -rf "$d"
}

test_remotion_is_documented_with_its_license_note() {
  local s; s=$(cat "$ROOT/remotion/README.md")
  assert_contains "$s" "licença" "fala da licença do Remotion"
  assert_contains "$s" "npm install" "como instalar"
  assert_contains "$s" "render-remotion.sh" "como renderizar"
}

_grupos_url() { # URL file:// do módulo (o Node do Windows não entende /c/Users/...)
  if command -v cygpath >/dev/null 2>&1; then printf 'file:///%s' "$(cygpath -m "$ROOT")/remotion/src/grupos.ts"; else printf 'file://%s' "$ROOT/remotion/src/grupos.ts"; fi
}

_node_ts() { # roda um módulo .ts com o Node (strip de tipos); pula o teste se esta versão do Node não suporta
  command -v node >/dev/null 2>&1 || return 2
  node --input-type=module -e "import('$(_grupos_url)').then(m => { if (!m.agruparPalavras) process.exit(3) })" >/dev/null 2>&1 || return 2
}

test_group_switch_prefers_the_new_group_over_the_lingering_one() {
  _node_ts || return 0
  local out
  out=$(node --input-type=module -e "
import {agruparPalavras, grupoAtual} from '$(_grupos_url)';
const p = [{texto:'a',inicio_s:0.3,fim_s:0.5},{texto:'b',inicio_s:0.5,fim_s:1.0},{texto:'c',inicio_s:1.0,fim_s:1.35},{texto:'d',inicio_s:1.35,fim_s:2.0},{texto:'e',inicio_s:2.0,fim_s:2.4}];
const g = agruparPalavras(p, 3);
const nome = (x) => x ? x.map(w => w.texto).join('') : 'nenhum';
console.log([0.1, 0.4, 1.4, 1.5, 2.5, 2.6, 3.5].map(t => nome(grupoAtual(g, t, 0.15))).join(','));
")
  assert_eq "nenhum,abc,de,de,de,nenhum,nenhum" "$out" "o grupo novo vence o antigo na troca e some depois da folga"
}

test_groups_do_not_cross_a_pause_between_sentences() {
  _node_ts || return 0
  local out
  out=$(node --input-type=module -e "
import {agruparPalavras} from '$(_grupos_url)';
const p = [{texto:'hoje',inicio_s:1.35,fim_s:2.0},{texto:'o',inicio_s:2.6,fim_s:2.7},{texto:'clo',inicio_s:2.7,fim_s:3.0},{texto:'app',inicio_s:3.0,fim_s:3.3}];
console.log(agruparPalavras(p, 3).map(g => g.map(w => w.texto).join('+')).join(' | '));
")
  assert_eq "hoje | o+clo+app" "$out" "uma pausa maior que 0,3 s começa um grupo novo"
}
