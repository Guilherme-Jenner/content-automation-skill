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
  _b confirm "$d/b.json" 100 >/dev/null 2>&1 || _fail "60+40 = teto deveria ser confirmável"
  _b spend "$d/b.json" a 60 >/dev/null 2>&1 || _fail "gasto a"
  _b spend "$d/b.json" b 40 >/dev/null 2>&1 || _fail "gasto b"
  assert_contains "$(_b status "$d/b.json")" "restante: 0" "nada restante"
  _b quote "$d/b.json" c 1 >/dev/null
  out=$(_b confirm "$d/b.json" 1 2>&1) && _fail "além do teto deveria ser recusado"
  assert_contains "$out" "excede" "mensagem"
  rm -rf "$d"
}

test_total_quote_above_ceiling_is_refused_before_any_spend() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" v1 60 >/dev/null; _b quote "$d/b.json" v2 50 >/dev/null
  assert_contains "$(_b status "$d/b.json")" "total cotado: 110" "mostra o total das N variantes"
  out=$(_b confirm "$d/b.json" 110 2>&1) && _fail "110 > 100 deveria ser recusado"
  assert_contains "$out" "excede" "mensagem"
  _b spend "$d/b.json" v1 60 >/dev/null 2>&1 && _fail "nada foi confirmado, não pode gastar"
  rm -rf "$d"
}

test_committed_spend_counts_against_later_quotes() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" a 60 >/dev/null; _b confirm "$d/b.json" 60 >/dev/null 2>&1
  _b quote "$d/b.json" b 50 >/dev/null
  out=$(_b confirm "$d/b.json" 50 2>&1) && _fail "60 comprometidos + 50 deveria exceder"
  assert_contains "$out" "excede" "mensagem"
  rm -rf "$d"
}

test_invalid_costs_are_rejected() {
  local d c; d="$(_new 100)"
  for c in -1 abc nan inf ""; do
    _b quote "$d/b.json" a "$c" >/dev/null 2>&1 && _fail "cotação inválida aceita: '$c'"
  done
  _b quote "$d/b.json" a 10 >/dev/null; _b confirm "$d/b.json" 10 >/dev/null 2>&1
  for c in -1 abc nan; do
    _b spend "$d/b.json" a "$c" >/dev/null 2>&1 && _fail "gasto inválido aceito: '$c'"
  done
  rm -rf "$d"
}

test_spend_within_quote_once_only() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" a 10 >/dev/null; _b confirm "$d/b.json" 10 >/dev/null 2>&1
  _b spend "$d/b.json" a 9.5 >/dev/null 2>&1 || _fail "gasto até a cotação deveria passar"
  out=$(_b spend "$d/b.json" a 1 2>&1) && _fail "gasto duplicado aceito"
  assert_contains "$out" "já foi" "mensagem"
  assert_contains "$(_b status "$d/b.json")" "gasto: 9.5" "gasto acumulado"
  rm -rf "$d"
}

test_overrun_is_recorded_and_blocks_the_item() {
  local d out rc; d="$(_new 100)"
  _b quote "$d/b.json" a 10 >/dev/null; _b confirm "$d/b.json" 10 >/dev/null 2>&1
  out=$(_b spend "$d/b.json" a 11 2>&1); rc=$?
  [ "$rc" -eq 3 ] || _fail "estouro deveria sair com código 3 (saiu com $rc)"
  assert_contains "$out" "estouro" "mensagem"
  assert_contains "$(_b status "$d/b.json")" "gasto: 11" "o valor efetivo fica registrado"
  assert_contains "$(_b status "$d/b.json")" "estourou" "item marcado"
  _b check "$d/b.json" a >/dev/null 2>&1 && _fail "item estourado/gasto não pode ser reutilizado"
  _b spend "$d/b.json" a 1 >/dev/null 2>&1 && _fail "não pode gastar de novo"
  rm -rf "$d"
}

test_unsafe_item_names_rejected() {
  local d i; d="$(_new 100)"
  for i in '../x' 'a b' '$(id)' ''; do
    _b quote "$d/b.json" "$i" 1 >/dev/null 2>&1 && _fail "item inseguro aceito: '$i'"
  done
  rm -rf "$d"
}

test_check_requires_confirmed_unspent_item() {
  local d out; d="$(_new 100)"
  out=$(_b check "$d/b.json" a 2>&1) && _fail "item sem cotação"
  assert_contains "$out" "cotação" "mensagem"
  _b quote "$d/b.json" a 10 >/dev/null
  out=$(_b check "$d/b.json" a 2>&1) && _fail "item não confirmado"
  assert_contains "$out" "confirm" "mensagem"
  _b confirm "$d/b.json" 10 >/dev/null 2>&1
  _b check "$d/b.json" a >/dev/null 2>&1 || _fail "item confirmado deveria passar"
  out=$(_b check "$d/b.json" a 12 2>&1) && _fail "custo atual acima do cotado deveria ser recusado"
  assert_contains "$out" "maior" "mensagem"
  _b check "$d/b.json" a 10 >/dev/null 2>&1 || _fail "custo atual igual ao cotado deveria passar"
  _b spend "$d/b.json" a 10 >/dev/null 2>&1
  _b check "$d/b.json" a >/dev/null 2>&1 && _fail "item já gasto"
  rm -rf "$d"
}

# I3 da revisão: a confirmação é amarrada ao total que o usuário viu -------------------
test_confirm_requires_the_total_shown_to_the_user() {
  local d out; d="$(_new 100)"
  _b quote "$d/b.json" a 10 >/dev/null
  out=$(_b confirm "$d/b.json" 11 2>&1) && _fail "total diferente do pendente deveria ser recusado"
  assert_contains "$out" "não bate" "mensagem"
  _b quote "$d/b.json" a 95 >/dev/null   # recotou depois de o usuário ver 10
  out=$(_b confirm "$d/b.json" 10 2>&1) && _fail "cotação mudou depois de mostrar o total"
  assert_contains "$out" "não bate" "mensagem"
  _b confirm "$d/b.json" 95 >/dev/null 2>&1 || _fail "total correto deveria confirmar"
  out=$(_b confirm "$d/b.json" 95 2>&1) && _fail "confirm repetido"
  rm -rf "$d"
}

# I1 da revisão: livro-caixa sob concorrência ---------------------------------------
test_concurrent_spends_are_not_lost() {
  local d i out; d="$(_new 1000)"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do _b quote "$d/b.json" "i$i" 10 >/dev/null; done
  _b confirm "$d/b.json" 120 >/dev/null 2>&1 || _fail "confirm falhou"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    (_b spend "$d/b.json" "i$i" 10 > "$d/out$i.txt" 2>&1) &
  done
  wait
  out=$(cat "$d"/out*.txt)
  case "$out" in *Traceback*) _fail "traceback em gasto concorrente: $out" ;; esac
  assert_contains "$(_b status "$d/b.json")" "gasto: 120" "nenhum gasto perdido"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    _b check "$d/b.json" "i$i" >/dev/null 2>&1 && _fail "item i$i ainda aparece como não gasto"
  done
  rm -rf "$d"
}

test_corrupt_budget_file_is_refused_not_a_traceback() {
  local d out; d="$(_new 100)"
  printf '{"teto": "100", "itens": {' > "$d/b.json"
  out=$(_b status "$d/b.json" 2>&1) && _fail "arquivo truncado aceito"
  assert_contains "$out" "corrompido" "mensagem"
  case "$out" in *Traceback*) _fail "não deveria vazar traceback" ;; esac
  rm -rf "$d"
}
