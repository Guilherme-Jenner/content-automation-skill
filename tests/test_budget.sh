#!/usr/bin/env bash
# Testes de scripts/budget.py (teto de gastos para qualquer coisa que consuma crédito)

_b() { python3 "$ROOT/scripts/budget.py" "$@"; }
_new() { local d; d="$(mktemp -d)"; _b init "$d/b.json" "$1" >/dev/null 2>&1 || _fail "init $1 falhou"; printf '%s' "$d"; }

test_init_rejects_invalid_ceilings() {
  local d t out; d="$(mktemp -d)"
  for t in 0 -5 abc nan inf "" 1e999; do
    out=$(_b init "$d/b.json" "$t" 2>&1) && _fail "teto inválido aceito: '$t'"
    assert_contains "$out" "teto" "mensagem cita o teto ('$t')"
    [ ! -e "$d/b.json" ] || _fail "não deveria criar arquivo ('$t')"
  done
  _b init "$d/b.json" 100 >/dev/null 2>&1 || _fail "teto 100 deveria ser aceito"
  out=$(_b init "$d/b.json" 200 2>&1) && _fail "init não pode sobrescrever um orçamento existente"
  assert_contains "$out" "já existe" "mensagem"
  rm -rf "$d"
}

test_nothing_is_spent_without_quote_and_confirmation() {
  local d out; d="$(_new 100)"
  out=$(_b spend "$d/b.json" a 10 2>&1) && _fail "gasto sem cotação aceito"
  assert_contains "$out" "cotação" "mensagem"
  _b quote "$d/b.json" a 10 >/dev/null
  out=$(_b spend "$d/b.json" a 10 2>&1) && _fail "gasto sem confirmação aceito"
  assert_contains "$out" "confirm" "mensagem"
  rm -rf "$d"
}

test_exactly_at_the_ceiling_is_allowed_and_then_blocked() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" a 60 >/dev/null; _b quote "$d/b.json" b 40 >/dev/null
  _b confirm "$d/b.json" >/dev/null 2>&1 || _fail "60+40 = teto deveria ser confirmável"
  _b spend "$d/b.json" a 60 >/dev/null 2>&1 || _fail "gasto a"
  _b spend "$d/b.json" b 40 >/dev/null 2>&1 || _fail "gasto b"
  assert_contains "$(_b status "$d/b.json")" "restante: 0" "nada restante"
  _b quote "$d/b.json" c 1 >/dev/null
  out=$(_b confirm "$d/b.json" 2>&1) && _fail "além do teto deveria ser recusado"
  assert_contains "$out" "excede" "mensagem"
  rm -rf "$d"
}

test_total_quote_above_ceiling_is_refused_before_any_spend() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" v1 60 >/dev/null; _b quote "$d/b.json" v2 50 >/dev/null
  assert_contains "$(_b status "$d/b.json")" "total cotado: 110" "mostra o total das N variantes"
  out=$(_b confirm "$d/b.json" 2>&1) && _fail "110 > 100 deveria ser recusado"
  assert_contains "$out" "excede" "mensagem"
  _b spend "$d/b.json" v1 60 >/dev/null 2>&1 && _fail "nada foi confirmado, não pode gastar"
  rm -rf "$d"
}

test_committed_spend_counts_against_later_quotes() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" a 60 >/dev/null; _b confirm "$d/b.json" >/dev/null 2>&1
  _b quote "$d/b.json" b 50 >/dev/null
  out=$(_b confirm "$d/b.json" 2>&1) && _fail "60 comprometidos + 50 deveria exceder"
  assert_contains "$out" "excede" "mensagem"
  rm -rf "$d"
}

test_invalid_costs_are_rejected() {
  local d c; d="$(_new 100)"
  for c in -1 abc nan inf ""; do
    _b quote "$d/b.json" a "$c" >/dev/null 2>&1 && _fail "cotação inválida aceita: '$c'"
  done
  _b quote "$d/b.json" a 10 >/dev/null; _b confirm "$d/b.json" >/dev/null 2>&1
  for c in -1 abc nan; do
    _b spend "$d/b.json" a "$c" >/dev/null 2>&1 && _fail "gasto inválido aceito: '$c'"
  done
  rm -rf "$d"
}

test_spend_cannot_exceed_quote_or_repeat() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" a 10 >/dev/null; _b confirm "$d/b.json" >/dev/null 2>&1
  out=$(_b spend "$d/b.json" a 11 2>&1) && _fail "gasto acima da cotação aceito"
  assert_contains "$out" "cotação" "mensagem"
  _b spend "$d/b.json" a 9.5 >/dev/null 2>&1 || _fail "gasto até a cotação deveria passar"
  out=$(_b spend "$d/b.json" a 1 2>&1) && _fail "gasto duplicado aceito"
  assert_contains "$out" "já foi" "mensagem"
  assert_contains "$(_b status "$d/b.json")" "gasto: 9.5" "gasto acumulado"
  rm -rf "$d"
}

test_unsafe_item_names_rejected() {
  local d i; d="$(_new 100)"
  for i in '../x' 'a b' '$(id)' ''; do
    _b quote "$d/b.json" "$i" 1 >/dev/null 2>&1 && _fail "item inseguro aceito: '$i'"
  done
  rm -rf "$d"
}
