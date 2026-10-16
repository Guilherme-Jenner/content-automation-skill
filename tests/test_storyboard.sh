#!/usr/bin/env bash
# Testes da skill script-storyboard e de scripts/check_durations.py

_d() { python3 "$ROOT/scripts/check_durations.py" "$ROOT/tests/data/$1"; }
_v() { python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/$1.schema.json" "$ROOT/tests/data/$2"; }

test_examples_validate_and_match_target() {
  _v storyboard storyboard_gerado.json 2>&1 || _fail "storyboard_gerado inválido"
  _v shot-list shot_list_gravado.json 2>&1 || _fail "shot_list_gravado inválido"
  _d storyboard_gerado.json || _fail "soma das cenas fora do alvo"
  _d shot_list_gravado.json || _fail "soma dos takes fora do alvo"
}

test_duration_mismatch_fails() {
  local out
  out=$(_d storyboard_short.json 2>&1) && _fail "deveria falhar com soma 20 s para alvo 30 s"
  assert_contains "$out" "soma" "mensagem explica a diferença"
}

test_skill_declares_both_modes() {
  local f="$ROOT/skills/script-storyboard/SKILL.md" txt
  assert_file_exists "$f"
  txt=$(cat "$f")
  assert_contains "$txt" "name: script-storyboard" "frontmatter name"
  assert_contains "$txt" "description:" "frontmatter description"
  assert_contains "$txt" "gerado" "modo gerado"
  assert_contains "$txt" "gravado" "modo gravado"
  assert_contains "$txt" "caminho do arquivo" "pede caminho do arquivo"
}
