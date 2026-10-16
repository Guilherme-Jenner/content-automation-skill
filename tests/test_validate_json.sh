#!/usr/bin/env bash
# Testes de scripts/validate_json.py

_v() { python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/$1.schema.json" "$ROOT/tests/data/$2"; }

test_valid_storyboard_passes() {
  _v storyboard storyboard_valid.json >/dev/null 2>&1 || _fail "storyboard válido foi rejeitado"
}

test_missing_field_names_the_path() {
  local out; out=$(_v storyboard storyboard_missing_field.json 2>&1) && _fail "deveria rejeitar"
  assert_contains "$out" "duracao_alvo_s" "campo ausente citado"
}

test_negative_duration_rejected() {
  local out; out=$(_v storyboard storyboard_negative_duration.json 2>&1) && _fail "deveria rejeitar"
  assert_contains "$out" "cenas[2].duracao_s" "caminho do campo"
}

test_cut_plan_requires_approved_field() {
  local out; out=$(_v cut-plan cutplan_no_approved.json 2>&1) && _fail "deveria rejeitar"
  assert_contains "$out" "approved" "campo approved citado"
}
