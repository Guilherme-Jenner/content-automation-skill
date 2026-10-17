#!/usr/bin/env bash
# O roteiro de validação com contas de teste deixa claro o que NÃO gasta e NÃO publica, e o que exige autorização

DOC="$ROOT/docs/validacao-contas-teste.md"

test_validation_guide_separates_safe_steps_from_steps_needing_approval() {
  local s; assert_file_exists "$DOC"; s=$(cat "$DOC")
  assert_contains "$s" "Não gasta crédito e não publica" "marca os passos seguros"
  assert_contains "$s" "Exige a sua autorização" "marca os passos que dependem do usuário"
  [ "$(grep -c 'Não gasta crédito e não publica' "$DOC")" -ge 3 ] || _fail "esperava ao menos 3 passos marcados como seguros"
  [ "$(grep -c 'Exige a sua autorização' "$DOC")" -ge 3 ] || _fail "esperava ao menos 3 passos que exigem autorização"
}

test_validation_guide_covers_scheduler_and_katana_with_evidence() {
  local s; s=$(cat "$DOC")
  assert_contains "$s" "Metricool" "agendador sugerido"
  assert_contains "$s" "URL pública" "limitação do Metricool"
  assert_contains "$s" "conta de teste" "nunca nos perfis reais"
  assert_contains "$s" "Katana" "validação do Katana"
  assert_contains "$s" "balance" "saldo antes e depois"
  assert_contains "$s" "transactions" "conferir transações"
  assert_contains "$s" "teto" "teto de gastos"
  assert_contains "$s" "ad-multiplier" "workflow avaliado"
  assert_contains "$s" "video-montage" "workflow avaliado"
  assert_contains "$s" "get_katana_config" "avisa que essa chamada cria sessão e não é consulta"
}

test_validation_guide_is_honest_about_unknowns() {
  local s; s=$(cat "$DOC")
  assert_contains "$s" "não verificado" "marca o que não foi verificado"
  assert_contains "$s" "Perguntas para você" "pede as decisões que só o usuário toma"
}
