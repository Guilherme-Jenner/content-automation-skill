#!/usr/bin/env bash
# A skill schedule-post e a orquestradora: aprovação humana, honestidade sobre o que não existe, plano B

test_schedule_skill_has_the_approval_gates() {
  local f="$ROOT/skills/schedule-post/SKILL.md" s
  assert_file_exists "$f"
  s=$(cat "$f")
  assert_contains "$s" "name: schedule-post" "frontmatter"
  assert_contains "$s" "research.json" "legenda e horários com base na pesquisa"
  assert_contains "$s" "propose_slots.py" "horários por cadência"
  assert_contains "$s" "validate_schedule.py" "valida o plano antes de mostrar"
  assert_contains "$s" "aprovo" "aprovação explícita do usuário"
  assert_contains "$s" "approval.py" "aprovação por hash"
  assert_contains "$s" "--confirm" "agendar de verdade exige --confirm"
  assert_contains "$s" "export_package.sh" "plano B manual"
  assert_contains "$s" "CLAUDE_PLUGIN_ROOT" "caminhos via raiz do plugin"
}

test_schedule_skill_is_honest_about_real_schedulers() {
  local s; s=$(cat "$ROOT/skills/schedule-post/SKILL.md")
  assert_contains "$s" "ainda não implementad" "agendadores reais ainda não existem"
  assert_contains "$s" "fake" "explica que o agendador existente é falso"
  assert_contains "$s" "nunca" "regra de nunca agendar/publicar sem aprovação"
}

test_orchestrator_hands_off_to_schedule_post() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "schedule-post" "usa a skill de agendamento"
  assert_contains "$s" "export_package" "oferece o pacote manual"
  assert_contains "$s" "ainda não implementad" "continua honesta sobre geração e Katana"
}
