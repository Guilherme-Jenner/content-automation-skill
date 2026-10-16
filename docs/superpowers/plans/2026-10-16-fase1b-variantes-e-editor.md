# Fase 1b — Variantes por bruto e escolha de editor — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que um vídeo bruto (gerado ou gravado) vire de 1 a 5 vídeos finais diferentes, com o usuário escolhendo o editor (`local` agora; `katana` depois, atrás de uma porta) e com teto de gastos para qualquer coisa que consuma crédito.

**Architecture:** Um `variants-plan.json` descreve as variantes; cada uma vira um `cut-plan` próprio e passa pelo pipeline já existente (`edit-recorded`), com aprovação separada. O editor é uma porta: `local` (ffmpeg, custo zero) e, na etapa 2, `katana` (real e falso). O teto de gastos é um módulo único usado por tudo que custa crédito.

**Tech Stack:** bash, python3 (stdlib), ffmpeg (igual à fase 1).

**Spec:** `docs/superpowers/specs/2026-10-16-clo-content-pipeline-design.md` (seção "Editor escolhido e várias variantes por bruto"). Depende da Fase 1 concluída (`docs/superpowers/plans/2026-10-16-fase1-roteiro-e-edicao-gravado.md`).

## Global Constraints
- As da Fase 1 (bash/POSIX, python3 stdlib, sem serviço pago nos testes, texto ao usuário em PT-BR, aprovação humana obrigatória).
- **Máximo de 5 variantes**, para qualquer editor. Mínimo 1.
- Gancho distinto por padrão em cada variante; repetir só com `gancho_repetido: true` e `justificativa_gancho` preenchida, e a skill avisa o usuário.
- Tipos de variante: `trecho_diferente` e `mesmo_trecho_edicao_diferente`.
- Editor `local` custa zero e não consome teto; qualquer outro editor passa pelo teto de gastos.
- **Ordem cronológica preservada** nesta fase (sem reordenar trechos); a variação vem de trechos mantidos, ritmo (margem/mínimo de silêncio), gancho e estilo de legenda. Reordenação fica para depois.
- Uma variante só roda se estiver `aprovada: true`; aprovar uma não aprova as outras.
- Saídas existentes não são sobrescritas sem `--force`; caminhos relativos funcionam (lições da revisão da Fase 1).

## Review Focus
- N = 0, N = 6 ou N não numérico → recusado com mensagem clara.
- Duas variantes `trecho_diferente` com trechos idênticos ou quase idênticos → aviso de redundância.
- Trechos de uma variante sobrepostos, fora da duração do bruto ou com menos de 1 s no total → rejeitados antes de rodar.
- Variantes com o mesmo gancho sem justificativa → rejeitadas.
- Uma variante aprovada e outra não → só a aprovada roda, e o resumo diz quais ficaram de fora.
- Falha no meio (variante 3 de 5) → as anteriores permanecem íntegras, nada parcial da falha, relato claro de quais concluíram.
- Teto: orçamento exato no limite, cotação maior que o saldo restante, valores negativos ou não numéricos → recusados; nada é gasto sem cotação e confirmação.

---

## Etapa 1 — variantes com o editor local (custo zero)

### Task 1: Contrato e validação do `variants-plan.json`

**Files:** Create `schemas/variants-plan.schema.json`, `scripts/validate_variants.py`, `tests/data/variants_valid.json`, `tests/test_variants_plan.sh`

**Interfaces:**
- Produces: formato `{bruto, editor: "local"|"katana", quantidade, duracao_s, variantes:[{id, tipo, trechos:[{inicio_s, fim_s}], gancho, gancho_repetido?, justificativa_gancho?, ritmo:{min_silencio_s, margem_s}, legenda_estilo, aprovada, achados:[string]}]}`. `python3 scripts/validate_variants.py <variants-plan.json>` sai 0 só se: valida no schema; `1 <= quantidade <= 5` e `len(variantes) == quantidade`; ids únicos; trechos ordenados, sem sobreposição, dentro de `[0, duracao_s]`, soma ≥ 1 s por variante; ganchos distintos ou repetição justificada; `achados` não vazio (liga a variante à pesquisa). Avisos (stderr, exit 0) para variantes `trecho_diferente` com trechos quase idênticos (sobreposição > 80 %).

- [ ] **Step 1:** Testes: `test_valid_plan_passes`; `test_quantity_out_of_range_rejected` (0 e 6, mensagem cita 5); `test_quantity_must_match_variants`; `test_duplicate_hook_needs_justification`; `test_overlapping_or_out_of_range_segments_rejected`; `test_short_total_rejected`; `test_redundant_variants_warn`; `test_variant_without_findings_rejected`.
- [ ] **Step 2–4:** Falhar, implementar (reaproveitar `validate_json.validar`), passar. **Step 5:** Commit.

### Task 2: Variante → plano de cortes

**Files:** Create `scripts/variant_to_cutplan.py`, `tests/test_variant_to_cutplan.sh`

**Interfaces:**
- Consumes: `variants-plan.json` (Task 1), formato `cut-plan` da Fase 1.
- Produces: `python3 scripts/variant_to_cutplan.py <variants-plan.json> <id> <video>` imprime um `cut-plan` com `cortes` = complemento dos `trechos` da variante, `approved` = `aprovada` da variante, `video` = caminho absoluto, `duracao_s` do plano. Variante inexistente → erro.

- [ ] **Step 1:** Testes: `test_complement_of_segments` (trechos [1,3] e [4,6] em 6,5 s → cortes [0,1], [3,4], [6,6.5]); `test_approval_is_per_variant`; `test_unknown_id_fails`; `test_result_validates_with_validate_cutplan`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 3: Aplicar várias variantes (`--variants`)

**Files:** Modify `scripts/edit-recorded.sh`; Create `tests/test_edit_variants_e2e.sh`

**Interfaces:**
- Consumes: Tasks 1–2; estágios `propose`/`apply` da Fase 1.
- Produces: `edit-recorded.sh <video> <dir> --stage apply --variants <variants-plan.json> [--force]`: valida o plano; para cada variante **aprovada**, gera `<dir>/v<id>/cut-plan.json` (Task 2) e roda o pipeline, produzindo `<dir>/final-<id>.mp4` e `final-<id>.srt`. Variantes não aprovadas são puladas e listadas no resumo (PT-BR). `propose` aceita `--variants-count N` (1–5) e grava um `variants-plan.json` inicial só com a estrutura (a proposta criativa é da skill). Estilo de legenda e ritmo da variante são repassados aos scripts (`subtitles.sh --style`, `silence-detect.sh --min-silence/--pad`).

- [ ] **Step 1:** Testes (transcritor falso): `test_three_variants_produce_three_outputs` (3 `final-N.mp4` 1080×1920 com durações ≈ soma dos trechos ±0,2); `test_only_approved_variants_run`; `test_failure_in_middle_keeps_previous_outputs`; `test_existing_output_needs_force`; `test_relative_paths_work`.
- [ ] **Step 2–4:** Falhar, implementar (adicionar `--style` ao `subtitles.sh`), passar. **Step 5:** Commit.

### Task 4: Skills — perguntas iniciais e proposta de variantes

**Files:** Modify `skills/content-pipeline/SKILL.md`, `skills/edit-recorded/SKILL.md`, `skills/research-trends/SKILL.md`; Create `tests/test_variants_skills.sh`

**Interfaces:**
- Produces: a orquestradora pergunta, no início da edição, (1) o editor (`local` ou `katana`; `katana` ainda não implementado, a skill avisa e oferece `local`) e (2) quantos vídeos finais (1 a 5; recusa mais que 5). `edit-recorded` instrui a propor as variantes a partir da transcrição, da pesquisa e do brief: gancho distinto por padrão, repetindo só se não houver outro bom na quantidade pedida (e dizendo isso), variando o resto; cada variante cita o `achado` que a justifica; aprovação **por variante**; valida com `validate_variants.py` antes de mostrar.

- [ ] **Step 1:** Testes: SKILL de orquestração contém `5` como limite, `local`, `katana` e "ainda não implementad"; `edit-recorded` contém `variants-plan.json`, `validate_variants.py`, "gancho", "aprovação" por variante; nenhum `bash scripts/`/`python3 scripts/` relativo.
- [ ] **Step 2–4:** Falhar, escrever, passar. **Step 5:** suíte completa + shellcheck; commit.

---

## Etapa 2 — Katana atrás de uma porta, com teto de gastos *(só depois da Etapa 1)*

Pré-requisito de desenho (ler, sem gastar): workflows `ad-multiplier` e `video-montage` do Higgsfield, para decidir qual encaixa melhor em "várias versões de um vídeo". Pontos já verificados: o `balance` devolve o saldo; gerações aceitam `get_cost: true` (cotação sem cobrança); o workflow do Katana é autônomo e **não pede confirmação de crédito**, então o teto é aplicado por nós antes de chamar. A chamada `get_katana_config` **cria sessão e pode gastar geração grátis**: nunca usar para consulta.

### Task 5: Módulo de teto de gastos (`scripts/budget.py`)
`init <teto>`, `quote <item> <custo>`, `confirm`, `spend <item> <custo>`, `status` sobre `budget.json`. Recusa: teto ≤ 0 ou não numérico; gasto sem cotação confirmada; gasto que ultrapasse o teto; negativo. Acumula; parar no teto. Testes cobrem exatamente no limite, acima do limite e N variantes cotadas em conjunto (custo total mostrado antes). Reutilizado pela geração (Fase 3).

### Task 6: Porta de editor e Katana falso
`scripts/editors/` com `local` (usa o pipeline da Etapa 1) e `katana-fake` (devolve vídeo de exemplo e custo fictício por variante). Seleção por `editor` no `variants-plan.json` ou `CLO_EDITOR`. Testes: o fake gasta crédito fictício, o teto bloqueia a variante que estouraria, as anteriores permanecem, `local` nunca toca o orçamento.

### Task 7: Adaptador `katana` real *(depende de validar com conta real)*
Só entra após validar com a conta: (a) envio do bruto (`media_upload` → PUT → `media_confirm`), (b) cotação antes de rodar, (c) download automatizado do resultado, (d) comportamento com o teto passado no pedido e conferência de saldo/`transactions` antes e depois. Nada deste task roda sem confirmação explícita do custo total pelo usuário.

---

## Auto-revisão
- **Cobertura:** escolha de editor (T4, T6), quantidade 1–5 (T1, T4), tipos de variante e gancho distinto/repetido (T1, T4), aprovação por variante (T2, T3), teto de gastos (T5–T7), custo zero no `local` (T3, T6).
- **Fora de escopo declarado:** reordenar trechos; escolha do workflow Higgsfield (`ad-multiplier` × `video-montage` × Katana) antes de ler suas instruções; Remotion (Fase 5).
- **Consistência:** `variants-plan.json` (T1) → `variant_to_cutplan.py` (T2) → `edit-recorded.sh --variants` (T3); `budget.py` (T5) é consumido por T6/T7 e pela geração da Fase 3.
