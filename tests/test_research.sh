#!/usr/bin/env bash
# Testes de scripts/check_research.py e das skills que exigem pesquisa

_cr() { python3 "$ROOT/scripts/check_research.py" "$@"; }

test_valid_research_passes() {
  _cr "$ROOT/tests/data/research_valid.json" 2>&1 || _fail "pesquisa válida foi rejeitada"
}

test_fact_without_source_rejected() {
  local out; out=$(_cr "$ROOT/tests/data/research_no_source.json" 2>&1) && _fail "deveria rejeitar"
  assert_contains "$out" "achados[1]" "aponta o achado"
  assert_contains "$out" "fonte_url" "aponta o campo"
}

test_too_few_findings_rejected() {
  local d out; d="$(mktemp -d)"
  python3 - "$ROOT/tests/data/research_valid.json" "$d/r.json" <<'PY'
import json, sys
dados = json.load(open(sys.argv[1], encoding="utf-8"))
dados["achados"] = dados["achados"][:2]
json.dump(dados, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_cr "$d/r.json" 2>&1) && _fail "deveria rejeitar"
  assert_contains "$out" "ao menos 3" "mensagem"
  rm -rf "$d"
}

test_non_http_source_rejected() {
  local d out; d="$(mktemp -d)"
  python3 - "$ROOT/tests/data/research_valid.json" "$d/r.json" <<'PY'
import json, sys
dados = json.load(open(sys.argv[1], encoding="utf-8"))
dados["achados"][0]["fonte_url"] = "pesquisei por conta propria"
json.dump(dados, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_cr "$d/r.json" 2>&1) && _fail "deveria rejeitar"
  assert_contains "$out" "achados[0]" "aponta o achado"
  rm -rf "$d"
}

test_hypothesis_may_lack_source() {
  _cr "$ROOT/tests/data/research_valid.json" >/dev/null 2>&1 || _fail "hipótese sem fonte deveria ser aceita"
}

test_skills_require_research() {
  local r s
  r=$(cat "$ROOT/skills/research-trends/SKILL.md" 2>/dev/null) || _fail "skill research-trends ausente"
  assert_contains "$r" "name: research-trends" "frontmatter"
  assert_contains "$r" "check_research.py" "valida a pesquisa"
  assert_contains "$r" "Nunca invente" "regra de não inventar fonte"
  s=$(cat "$ROOT/skills/script-storyboard/SKILL.md")
  assert_contains "$s" "research.json" "roteiro exige pesquisa"
}
