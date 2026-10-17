#!/usr/bin/env bash
# As skills perguntam editor e quantidade (máx. 5) e conduzem a proposta de variantes

test_orchestrator_asks_editor_and_quantity() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "editor" "pergunta o editor"
  assert_contains "$s" "local" "editor local"
  assert_contains "$s" "katana" "editor katana"
  assert_contains "$s" "de 1 a 5" "limite de 5 vídeos"
  assert_contains "$s" "ainda não implementad" "katana pendente declarado"
  assert_contains "$s" "teto" "teto de gastos"
}

test_edit_skill_drives_variants() {
  local s; s=$(cat "$ROOT/skills/edit-recorded/SKILL.md")
  assert_contains "$s" "variants-plan.json" "usa o plano de variantes"
  assert_contains "$s" "validate_variants.py" "valida o plano"
  assert_contains "$s" "gancho distinto" "gancho distinto por padrão"
  assert_contains "$s" "repita um gancho" "repetição permitida quando faltar gancho"
  assert_contains "$s" "trecho_diferente" "tipo trecho_diferente"
  assert_contains "$s" "mesmo_trecho_edicao_diferente" "tipo mesmo trecho"
  assert_contains "$s" "cada variante" "aprovação por variante"
  assert_contains "$s" "--variants" "aplica com --variants"
}

test_variant_rules_match_the_validator_limit() {
  # o limite citado nas skills é o mesmo do validador
  grep -q 'MAX_VARIANTES = 5' "$ROOT/scripts/validate_variants.py" || _fail "limite do validador mudou; atualize as skills"
}
