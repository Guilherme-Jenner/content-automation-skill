#!/usr/bin/env bash
# Empacotamento: marketplace do repositório, manifesto do plugin, guia de instalação/atualização e processo de release

test_marketplace_and_manifest_are_consistent() {
  python3 - "$ROOT" <<'PY' || _fail "marketplace.json ou plugin.json inconsistentes"
import json, os, re, sys
raiz = sys.argv[1]
m = json.load(open(os.path.join(raiz, ".claude-plugin", "marketplace.json"), encoding="utf-8"))
p = json.load(open(os.path.join(raiz, ".claude-plugin", "plugin.json"), encoding="utf-8"))
assert re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", m["name"]), "nome do marketplace"
assert not re.match(r"(claude-|anthropic-|anthropics-|cc-plugin-)", m["name"]), "prefixo reservado no marketplace"
assert not re.match(r"(claude-|anthropic-|anthropics-|cc-plugin-)", p["name"]), "prefixo reservado no plugin"
assert m["owner"]["name"], "owner.name"
assert len(m["plugins"]) == 1
e = m["plugins"][0]
assert e["name"] == p["name"], "o nome da entrada deve ser igual ao do plugin.json"
assert e["source"] == ".", "plugin na raiz do repositório"
assert "version" not in e, "version só no plugin.json (se estiver nos dois, o plugin.json vence sem aviso)"
assert re.fullmatch(r"\d+\.\d+\.\d+", p["version"]), "versão semântica"
assert p["license"] == "MIT"
assert p["author"]["name"]
assert "repository" not in p or p["repository"].startswith("https://"), "repository"
PY
}

test_changelog_matches_the_manifest_version() {
  local v; v=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8'))['version'])" "$ROOT/.claude-plugin/plugin.json")
  assert_file_exists "$ROOT/CHANGELOG.md"
  assert_contains "$(cat "$ROOT/CHANGELOG.md")" "## $v" "o CHANGELOG tem a seção da versão atual ($v)"
}

test_every_skill_has_valid_frontmatter() {
  local f name bad=""
  for f in "$ROOT"/skills/*/SKILL.md; do
    name=$(sed -n 's/^name: *//p' "$f" | head -1)
    [ "$name" = "$(basename "$(dirname "$f")")" ] || bad="$bad $f"
    [ -n "$(sed -n 's/^description: *//p' "$f" | head -1)" ] || bad="$bad $f(sem description)"
  done
  [ -z "$bad" ] || _fail "skills com frontmatter incorreto:$bad"
}

test_install_guide_covers_marketplace_update_and_auto_update() {
  local s; s=$(cat "$ROOT/docs/guia-mac-socio.md")
  assert_contains "$s" "/plugin marketplace add" "como adicionar o marketplace"
  assert_contains "$s" "/plugin install clo-content-pipeline@" "como instalar"
  assert_contains "$s" "Enable auto-update" "como ligar a atualização automática (vem desligada)"
  assert_contains "$s" "/plugin marketplace update" "atualização manual"
  assert_contains "$s" "brew install ffmpeg" "dependências do Mac"
}

test_release_process_is_documented() {
  local s; s=$(cat "$ROOT/docs/publicacao.md")
  assert_contains "$s" "version" "bump de versão"
  assert_contains "$s" "CHANGELOG" "changelog"
  assert_contains "$s" "claude plugin validate" "validação antes de publicar"
  assert_contains "$s" "repositório privado" "credenciais do GitHub se o repo for privado"
  assert_contains "$s" "próxima sessão" "a atualização vale na próxima sessão ou /reload-plugins"
}

test_no_local_paths_or_secrets_in_tracked_files() {
  local hits
  hits=$(cd "$ROOT" && git ls-files 2>/dev/null | grep -v '^tests/' | xargs grep -lE 'C:\\Users\\|/c/Users/|guilherme|clozetaplication|api[_-]?key *[:=]|Bearer [A-Za-z0-9]' 2>/dev/null | head -5) || true
  [ -z "$hits" ] || _fail "arquivos com caminho local ou dado pessoal: $hits"
}

test_guides_use_the_real_repository_address() {
  local alvo="Guilherme-Jenner/content-automation-skill"
  assert_contains "$(cat "$ROOT/docs/guia-mac-socio.md")" "/plugin marketplace add $alvo" "guia do Mac com o endereço real"
  assert_contains "$(cat "$ROOT/docs/publicacao.md")" "claude plugin marketplace add $alvo" "guia de publicação com o endereço real"
  python3 - "$ROOT/.claude-plugin/plugin.json" "$alvo" <<'PY' || _fail "plugin.json sem o campo repository correto"
import json, sys
assert json.load(open(sys.argv[1], encoding="utf-8"))["repository"] == "https://github.com/" + sys.argv[2]
PY
  case "$(cat "$ROOT/docs/guia-mac-socio.md" "$ROOT/docs/publicacao.md")" in *"OWNER/REPO"*) _fail "ainda há o marcador OWNER/REPO";; esac
}
