#!/usr/bin/env bash
# A skill edit-generated e a orquestradora: aprovação, licença da música, sem custo, honestidade

test_edit_generated_skill_has_the_gates() {
  local f="$ROOT/skills/edit-generated/SKILL.md" s
  assert_file_exists "$f"
  s=$(cat "$f")
  assert_contains "$s" "name: edit-generated" "frontmatter"
  assert_contains "$s" "research.json" "legendas ligadas à pesquisa"
  assert_contains "$s" "captions-plan.json" "plano de legendas"
  assert_contains "$s" "aprovo" "aprovação explícita do usuário"
  assert_contains "$s" "edit-generated.sh" "script de edição"
  assert_contains "$s" "assemble-clips.sh" "vem do vídeo montado"
  assert_contains "$s" "CLAUDE_PLUGIN_ROOT" "caminhos via raiz do plugin"
  assert_contains "$s" "--volume-db" "volume da trilha"
}

test_edit_generated_skill_is_honest_about_music_and_cost_and_gaps() {
  local s; s=$(cat "$ROOT/skills/edit-generated/SKILL.md")
  assert_contains "$s" "licença" "a licença da música é do usuário"
  assert_contains "$s" "não gasta crédito" "nenhum passo desta etapa gasta crédito"
  assert_contains "$s" "não baixe" "nada de baixar música protegida"
  assert_contains "$s" "ainda não implementad" "variantes e motion do modo gerado"
  assert_contains "$s" "conteúdo de IA" "lembra a declaração de IA ao publicar"
  assert_contains "$s" "51" "limite de caracteres por legenda (padrao)"
}

test_orchestrator_uses_edit_generated() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "edit-generated" "usa a skill de edição do modo gerado"
  assert_contains "$s" "ainda não implementad" "continua honesta sobre o que falta"
}
