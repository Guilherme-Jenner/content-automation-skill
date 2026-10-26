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
  assert_contains "$s" "validado em execução" "diz o que foi validado com a conta real"
  assert_contains "$s" "Instagram, vídeo e publicação real" "diz o que ainda NÃO foi validado"
  assert_contains "$s" "modo teste" "começa em modo teste"
  assert_contains "$s" "fake" "explica que o agendador existente é falso"
  assert_contains "$s" "nunca" "regra de nunca agendar/publicar sem aprovação"
}

test_orchestrator_hands_off_to_schedule_post() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "schedule-post" "usa a skill de agendamento"
  assert_contains "$s" "export_package" "oferece o pacote manual"
  assert_contains "$s" "ainda não implementad" "continua honesta sobre geração e Katana"
}

test_schedule_skill_documents_recovery_and_fixed_log() {
  local s; s=$(cat "$ROOT/skills/schedule-post/SKILL.md")
  assert_contains "$s" "--approvals" "comando completo do schedule.sh"
  assert_contains "$s" ".schedule-log.json" "log fixo ao lado do plano"
  assert_contains "$s" "supersede" "como reagendar um post já agendado"
  assert_contains "$s" "--conferido" "como liberar uma reserva órfã"
  assert_contains "$s" "conferir no agendador" "antes de liberar, conferir no agendador"
  assert_contains "$s" "--now" "proíbe --now fora dos testes"
  assert_contains "$s" "procedimento" "diz que a aprovação é de procedimento, não criptográfica"
}
