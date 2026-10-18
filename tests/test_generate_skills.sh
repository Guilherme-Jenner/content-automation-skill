#!/usr/bin/env bash
# A skill generate-clips e a orquestradora: teto, aprovação do total, honestidade sobre o que não foi validado

test_generate_skill_has_the_cost_gates() {
  local f="$ROOT/skills/generate-clips/SKILL.md" s
  assert_file_exists "$f"
  s=$(cat "$f")
  assert_contains "$s" "name: generate-clips" "frontmatter"
  assert_contains "$s" "storyboard_to_genplan.py" "converte o storyboard"
  assert_contains "$s" "budget.py" "teto de gastos"
  assert_contains "$s" "init" "cria o orçamento"
  assert_contains "$s" "get_cost" "cota sem cobrar"
  assert_contains "$s" "register-quote" "registra a cotação"
  assert_contains "$s" "confirm" "confirma o total"
  assert_contains "$s" "aprovo" "aprovação explícita do usuário"
  assert_contains "$s" "generate_video" "ferramenta do Higgsfield"
  assert_contains "$s" "jobs_wait" "espera do job"
  assert_contains "$s" "--stage register" "registra o clipe baixado"
  assert_contains "$s" "assemble-clips.sh" "monta os clipes"
  assert_contains "$s" "CLAUDE_PLUGIN_ROOT" "caminhos via raiz do plugin"
}

test_generate_skill_forbids_free_or_unlimited_flags_and_resubmission() {
  local s; s=$(cat "$ROOT/skills/generate-clips/SKILL.md")
  assert_contains "$s" "use_unlim" "cita a proibição"
  assert_contains "$s" "use_free_gens" "cita a proibição"
  assert_contains "$s" "get_katana_config" "avisa que não é consulta"
  assert_contains "$s" "não reenvie" "timeout de submissão"
  case "$s" in
    *'"use_unlim": true'*|*'use_unlim: true'*|*'"use_free_gens": true'*|*'use_free_gens: true'*) _fail "a skill não pode mandar ligar use_unlim/use_free_gens" ;;
  esac
}

test_generate_skill_is_honest_about_what_is_unverified() {
  local s; s=$(cat "$ROOT/skills/generate-clips/SKILL.md")
  assert_contains "$s" "não verificado" "marca o que não foi verificado"
  assert_contains "$s" "baixa" "a baixa automatizada do resultado"
  assert_contains "$s" "conteúdo de IA" "declarar conteúdo gerado por IA ao publicar"
  assert_contains "$s" "execução em paralelo" "não gerar em paralelo sem necessidade"
}

test_orchestrator_uses_generate_clips() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "generate-clips" "usa a skill de geração"
  assert_contains "$s" "teto" "teto de gastos"
  assert_contains "$s" "ainda não implementad" "continua honesta sobre o que falta"
}

test_generate_skill_explains_the_effective_cost_and_what_was_never_tested() {
  local s; s=$(cat "$ROOT/skills/generate-clips/SKILL.md")
  assert_contains "$s" "balance" "custo efetivo pela diferença de saldo"
  assert_contains "$s" "transactions" "ou pelas transações"
  assert_contains "$s" "nunca repita a cotação" "não copiar a cotação como se fosse o custo efetivo"
  assert_contains "$s" "Validado com a conta real" "registra o que foi validado com uma geração real"
  assert_contains "$s" "credits_exact" "documenta o formato real da resposta do get_cost"
  assert_contains "$s" "baixado-" "avisa para não baixar direto para clips/ (o register copia e recusa se existir)"
  assert_contains "$s" "UUID" "formato do job_id não validado"
}

test_generate_skill_documents_the_one_shot_payload_and_the_ceiling_exits() {
  local s; s=$(cat "$ROOT/skills/generate-clips/SKILL.md")
  assert_contains "$s" "--reemitir" "reemissão só depois de conferir o job"
  assert_contains "$s" "raise" "aumentar o teto é decisão do usuário"
  assert_contains "$s" "drop" "descartar itens"
  assert_contains "$s" "ultrapass" "depois de um estouro nada novo é gerado sem decisão do usuário"
}
