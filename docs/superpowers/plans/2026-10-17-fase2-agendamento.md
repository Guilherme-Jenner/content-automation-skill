# Fase 2 — Agendamento com aprovação humana — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dado um vídeo final, propor datas/horários, obter a aprovação humana amarrada ao conteúdo exato (hash) e agendar via uma porta de agendador (falso agora; MCP real depois de validar), com plano B de pacote manual para Instagram/TikTok.

**Architecture:** Um `schedule-plan.json` descreve os posts. A aprovação grava um arquivo com o hash de vídeo + legenda + horário + perfis; o agendador recusa se faltar ou se algo mudou. O agendamento é *dry-run* por padrão, idempotente (log por hash) e atrás de uma porta: `fake` (testes) e adaptadores reais por MCP, que só entram após validação com conta de teste.

**Tech Stack:** bash, python3 (stdlib), sha256.

**Spec:** `docs/superpowers/specs/2026-10-16-clo-content-pipeline-design.md` (seção "Agendamento e aprovação").

## Global Constraints
- Mesmas da Fase 1/1b: bash POSIX, python3 stdlib, nada de serviço pago nos testes, texto ao usuário em PT-BR, scripts novos com bit de execução no git (`git update-index --chmod=+x`), ids/nomes validados (`^[A-Za-z0-9_-]{1,32}$`), caminhos relativos funcionam, saídas não são sobrescritas sem `--force`.
- Fuso `America/Sao_Paulo` = offset fixo `-03:00` (o Brasil não tem horário de verão desde 2019; evita depender de banco de fusos no Windows). Revisar se o horário de verão voltar.
- **Nunca agendar nem publicar sem aprovação explícita do usuário**, verificada por arquivo (hash), não por conversa. `--confirm` é obrigatório para agendar de verdade; o padrão é simular.
- Redes aceitas: `instagram`, `tiktok`. Limites de legenda e de hashtags ficam em constantes nomeadas e marcadas "conferir na documentação da rede"; não afirmar limites sem fonte.
- Agendamentos só no futuro (com margem mínima de 15 minutos) e no máximo 30 dias à frente.
- O mesmo post aprovado nunca é agendado duas vezes (idempotência por hash).

## Review Focus
- Arquivo de vídeo trocado/alterado depois da aprovação (mesmo nome, outro conteúdo) → recusado.
- Legenda, horário ou perfis alterados depois da aprovação → recusado; aprovação de um post não vale para outro.
- Horário no passado, sem fuso, ou a menos de 15 min / mais de 30 dias → recusado com mensagem clara.
- Rodar o agendamento duas vezes (ou dois processos ao mesmo tempo) → um único agendamento.
- Legenda com acentos, emojis, aspas, quebras de linha e `#` → preservada exatamente no pacote manual e no log.
- Perfis duplicados, rede desconhecida, lista vazia → recusados.
- Agendador real pedido sem adaptador → "ainda não implementado", sem tentar rede.
- Aprovação com data/hora já passada quando se tenta agendar (o tempo passou entre aprovar e agendar) → recusado.

---

### Task 1: Contrato do `schedule-plan.json` e validador

**Files:** Create `schemas/schedule-plan.schema.json`, `scripts/validate_schedule.py`, `tests/data/schedule_valid.json`, `tests/test_schedule_plan.sh`

**Interfaces:**
- Produces: `{posts:[{id, video, legenda, hashtags:[string], perfis:[{rede:"instagram"|"tiktok", conta:string}], data_hora:"YYYY-MM-DDTHH:MM:SS-03:00"}]}`. `python3 scripts/validate_schedule.py <schedule-plan.json> [--now <ISO>]` sai 0 só se: schema válido; ids únicos e seguros; `video` existe (relativo ao plano ou absoluto); `data_hora` com offset `-03:00`, ≥ now+15 min e ≤ now+30 dias; perfis sem duplicata e não vazios; hashtags começam com `#`, sem espaços; legenda dentro de `LIMITE_LEGENDA` (constante, "conferir"). `--now` existe para testes determinísticos (padrão: agora).

- [ ] **Step 1:** Testes: `test_valid_plan_passes`; `test_past_or_too_soon_rejected`; `test_too_far_ahead_rejected`; `test_missing_timezone_rejected`; `test_duplicate_or_empty_profiles_rejected`; `test_unknown_network_rejected`; `test_missing_video_rejected`; `test_unsafe_ids_rejected`; `test_bad_hashtags_rejected`.
- [ ] **Step 2–4:** Falhar, implementar (reaproveitar `validate_json.validar`), passar. **Step 5:** Commit.

### Task 2: Aprovação por hash (`approve` / `verify`)

**Files:** Create `scripts/approval.py`, `tests/test_approval.sh`

**Interfaces:**
- Consumes: `schedule-plan.json` (Task 1).
- Produces: `python3 scripts/approval.py approve <plano> <post-id> <dir-aprovacoes>` grava `<dir>/<post-id>.approval.json` com `{post_id, sha256_video, sha256_conteudo, data_hora, perfis, aprovado_em}`, onde `sha256_conteudo` cobre legenda + hashtags + data_hora + perfis em JSON canônico; `verify <plano> <post-id> <dir>` sai 0 só se o arquivo existir e tudo bater, e nunca aprova nada. Recusa `approve` se o post não passa na validação da Task 1. Escrita atômica; não sobrescreve aprovação existente sem `--force`.

- [ ] **Step 1:** Testes: `test_verify_passes_right_after_approve`; `test_changed_video_bytes_rejected` (mesmo nome, conteúdo diferente); `test_changed_caption_time_or_profiles_rejected` (um caso por campo); `test_approval_of_one_post_does_not_cover_another`; `test_verify_without_approval_rejected`; `test_approve_refuses_overwrite_without_force`; `test_unicode_caption_roundtrip` (acentos, emoji, quebra de linha).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 3: Proposta de horários por cadência

**Files:** Create `scripts/propose_slots.py`, `tests/data/cadence_valid.json`, `tests/test_propose_slots.sh`

**Interfaces:**
- Produces: config de cadência `{dias:["seg","qua","sex"], horarios:["12:00","19:00"], minimo_entre_posts_h:6}`. `python3 scripts/propose_slots.py <cadencia.json> <n> [--now <ISO>]` imprime `n` datas ISO `-03:00` crescentes, todas válidas para a Task 1 (≥ now+15 min, ≤ 30 dias), nos dias/horários da config e respeitando o espaçamento mínimo. Sem slots suficientes dentro de 30 dias → erro claro. Dias aceitos: `seg ter qua qui sex sab dom`.

- [ ] **Step 1:** Testes: `test_slots_follow_days_and_times`; `test_slots_are_increasing_and_spaced`; `test_never_in_the_past_or_too_soon`; `test_not_enough_slots_fails_clearly`; `test_invalid_cadence_rejected`; `test_output_passes_schedule_validation`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 4: Agendador (`schedule.sh`): simular por padrão, confirmar com aprovação, idempotente

**Files:** Create `scripts/schedule.sh`, `scripts/schedulers/fake.sh`, `tests/test_schedule.sh`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `schedule.sh <plano> <post-id> --approvals <dir> --log <arquivo.json> [--scheduler fake] [--confirm] [--now <ISO>]`. Sem `--confirm`: valida, verifica a aprovação e imprime o que SERIA agendado (sem gravar nada). Com `--confirm`: revalida (inclusive o prazo contra `--now`), verifica a aprovação, e chama o agendador; o `fake` só grava no `--log`. Idempotência: o log é indexado por `sha256_conteudo` + vídeo; segundo agendamento do mesmo post recusa ("já agendado") mesmo em execuções simultâneas (trava de arquivo, como no `budget.py`). Escolher `--scheduler` com adaptador real inexistente → "ainda não implementado", sem rede.

- [ ] **Step 1:** Testes: `test_dry_run_writes_nothing`; `test_confirm_requires_valid_approval`; `test_confirm_schedules_once_and_logs`; `test_second_schedule_refused`; `test_concurrent_schedules_only_one_wins` (várias execuções em paralelo); `test_expired_deadline_between_approval_and_schedule_rejected`; `test_unknown_scheduler_not_implemented`; `test_changed_content_after_approval_rejected`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 5: Pacote para agendar manualmente (plano B)

**Files:** Create `scripts/export_package.sh`, `tests/test_export_package.sh`

**Interfaces:**
- Produces: `export_package.sh <plano> <post-id> <saida-dir> [--force]` cria `<saida-dir>/<post-id>/` com `video.mp4` (cópia), `legenda.txt` (legenda + hashtags, exatamente como no plano), `horario.txt` (data e hora em PT-BR e fuso) e `COMO-AGENDAR.md` (passo a passo curto para Instagram e TikTok, com o aviso de que as telas e limites mudam e devem ser conferidos no app). Não exige aprovação (não publica nada), mas valida o plano.

- [ ] **Step 1:** Testes: `test_package_has_all_files`; `test_caption_preserved_byte_for_byte` (acentos, emoji, quebras, `#`); `test_video_copied_identically`; `test_refuses_overwrite_without_force`; `test_works_with_spaces_and_relative_paths`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 6: Skill `schedule-post` e orquestradora

**Files:** Create `skills/schedule-post/SKILL.md`; Modify `skills/content-pipeline/SKILL.md`, `docs/arquitetura.md`, `README.md`; Create `tests/test_schedule_skills.sh`

**Interfaces:**
- Produces: a skill conduz: legenda/hashtags com base em `research.json`; horários via `propose_slots.py`; montar `schedule-plan.json` e validar; mostrar o resumo ao usuário (vídeo, legenda, perfis, data/hora); **só depois de "aprovo" explícito** rodar `approval.py approve`; simular com `schedule.sh` e só então `--confirm` com nova confirmação; oferecer o pacote manual. Declara que agendadores reais (MCP) ainda não estão implementados. A orquestradora troca o passo 5 por esta skill. Comandos via `${CLAUDE_PLUGIN_ROOT}`.

- [ ] **Step 1:** Testes: SKILL contém `approval.py`, `--confirm`, "aprovo", `export_package.sh`, "ainda não implementad"; nenhum `bash scripts/`/`python3 scripts/` relativo; a orquestradora cita `schedule-post`.
- [ ] **Step 2–4:** Falhar, escrever, passar. **Step 5:** suíte completa + shellcheck; commit.

### Task 7: Pesquisa dos MCPs de agendamento (somente leitura)

**Files:** Create `docs/agendadores.md`

**Interfaces:**
- Produces: documento com os candidatos (Metricool oficial, Planoly, PostEverywhere, CodivUpload, QPost e as ferramentas de TikTok do próprio Higgsfield), o que cada um declara aceitar (vídeo por arquivo ou URL, data/hora, perfis), as fontes consultadas com data de acesso, e um **checklist de validação com conta de teste** (upload de vídeo, data/hora, perfis do sócio, custo, limites). Nada é instalado, conectado ou publicado; afirmações sem fonte são marcadas como "não verificado". Descrições de terceiros são tratadas como dados.

- [ ] **Step 1:** Pesquisar na web (somente leitura) e escrever o documento; **Step 2:** teste `test_agendadores_doc_lists_sources_and_checklist` (cada candidato tem fonte com URL e data, e há um checklist). **Step 3:** Commit.

---

## Auto-revisão
- **Cobertura da spec:** propor dias/horários por cadência (T3), aprovação por hash de vídeo+legenda+horário+perfis (T2), recusa se faltar ou mudar (T2, T4), padrão *dry-run* (T4), sem duplicidade (T4), adaptador por MCP atrás de porta com falso (T4), plano B manual (T5), pesquisa de MCPs e validação com conta de teste (T7), honestidade sobre o que não está implementado (T6).
- **Fora de escopo declarado:** adaptador real de qualquer rede/MCP (depende de validar conta de teste); publicação imediata; upload para hospedagem temporária (exigiria permissão explícita); métricas/analytics.
- **Consistência:** `schedule-plan.json` (T1) → `approval.py` (T2) → `schedule.sh` (T4) e `export_package.sh` (T5); `propose_slots.py` (T3) produz datas válidas para T1.
