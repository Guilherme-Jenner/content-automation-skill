#!/usr/bin/env bash
# Teto de gastos OPCIONAL: o usuário escolhe, ao iniciar o fluxo, se quer definir um teto; sem teto, a cotação, a
# confirmação do total e o registro do gasto continuam valendo.

_b() { python3 "$ROOT/scripts/budget.py" "$@"; }

test_init_without_ceiling_is_accepted_and_reported() {
  local d out; d="$(mktemp -d)"
  _b init "$d/b.json" sem-teto >/dev/null || _fail "init sem-teto recusado"
  out=$(_b status "$d/b.json") || _fail "status falhou"
  assert_contains "$out" "sem teto" "status diz que não há teto"
  case "$out" in *restante*) _fail "sem teto não existe 'restante'";; esac
  rm -rf "$d"
}

test_without_ceiling_quote_confirm_spend_still_work() {
  local d out; d="$(mktemp -d)"
  _b init "$d/b.json" sem-teto >/dev/null
  _b quote "$d/b.json" clip-a 40 >/dev/null || _fail "quote falhou"
  _b quote "$d/b.json" clip-b 60 >/dev/null || _fail "quote falhou"
  out=$(_b confirm "$d/b.json" 100) || _fail "confirm do total falhou: $out"
  assert_contains "$out" "sem teto" "avisa que não há teto"
  _b confirm "$d/b.json" 1 >/dev/null 2>&1 && _fail "confirm tem de continuar exigindo o total certo"
  _b check "$d/b.json" clip-a 40 >/dev/null || _fail "check de item confirmado falhou"
  _b spend "$d/b.json" clip-a 40 >/dev/null || _fail "spend falhou"
  assert_contains "$(_b status "$d/b.json")" "gasto" "status mostra o gasto"
  rm -rf "$d"
}

test_without_ceiling_confirm_still_requires_the_exact_total() {
  local d out; d="$(mktemp -d)"
  _b init "$d/b.json" sem-teto >/dev/null; _b quote "$d/b.json" clip-a 40 >/dev/null
  out=$(_b confirm "$d/b.json" 39 2>&1) && _fail "total errado aceito"
  assert_contains "$out" "40" "mostra o total certo"
  rm -rf "$d"
}

test_a_ceiling_can_be_added_later_but_not_below_commitments() {
  local d out; d="$(mktemp -d)"
  _b init "$d/b.json" sem-teto >/dev/null; _b quote "$d/b.json" clip-a 40 >/dev/null; _b confirm "$d/b.json" 40 >/dev/null
  out=$(_b raise "$d/b.json" 30 2>&1) && _fail "teto abaixo dos compromissos aceito"
  _b raise "$d/b.json" 100 >/dev/null || _fail "definir um teto depois falhou"
  assert_contains "$(_b status "$d/b.json")" "100" "teto definido"
  rm -rf "$d"
}

test_with_ceiling_nothing_changes() {
  local d out; d="$(mktemp -d)"
  _b init "$d/b.json" 50 >/dev/null; _b quote "$d/b.json" clip-a 60 >/dev/null
  out=$(_b confirm "$d/b.json" 60 2>&1) && _fail "total acima do teto aceito"
  assert_contains "$out" "teto" "mensagem do teto"
  _b init "$d/c.json" 0 >/dev/null 2>&1 && _fail "teto 0 aceito"
  _b init "$d/e.json" "talvez" >/dev/null 2>&1 && _fail "texto qualquer aceito como teto"
  rm -rf "$d"
}

test_skills_ask_for_an_optional_ceiling_at_the_start() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "sem-teto" "orquestradora oferece iniciar sem teto"
  assert_contains "$s" "opcional" "o teto é opcional"
  assert_contains "$(cat "$ROOT/skills/generate-clips/SKILL.md")" "sem-teto" "generate-clips aceita orçamento sem teto"
}
