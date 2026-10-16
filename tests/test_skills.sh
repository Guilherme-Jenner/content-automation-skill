#!/usr/bin/env bash
# Valida o frontmatter de todas as skills e o plugin.json

test_skills_have_valid_frontmatter() {
  local dir name want desc count=0
  for dir in "$ROOT"/skills/*/; do
    want="$(basename "$dir")"
    [ -f "$dir/SKILL.md" ] || { _fail "$want sem SKILL.md"; continue; }
    name="$(sed -n 's/^name: *//p' "$dir/SKILL.md" | head -1 | tr -d '\r')"
    desc="$(sed -n 's/^description: *//p' "$dir/SKILL.md" | head -1)"
    assert_eq "$want" "$name" "name da skill $want"
    [ -n "$desc" ] || _fail "skill $want sem description"
    count=$((count + 1))
  done
  [ "$count" -ge 4 ] || _fail "esperava ao menos 4 skills, achei $count"
}

test_plugin_json_is_valid() {
  python3 -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); assert d['name']=='clo-content-pipeline' and d['version']" "$ROOT/.claude-plugin/plugin.json" \
    || _fail "plugin.json inválido"
}

test_orchestrator_covers_modes_gates_and_pending_stages() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md" 2>/dev/null) || { _fail "content-pipeline ausente"; return; }
  assert_contains "$s" "gerado" "modo gerado"
  assert_contains "$s" "gravado" "modo gravado"
  assert_contains "$s" "script-storyboard" "chama roteiro"
  assert_contains "$s" "edit-recorded" "chama edição"
  assert_contains "$s" "research-trends" "pesquisa"
  assert_contains "$s" "ainda não implementad" "etapas pendentes declaradas"
  assert_contains "$s" "aprovação" "aprovação humana"
}
