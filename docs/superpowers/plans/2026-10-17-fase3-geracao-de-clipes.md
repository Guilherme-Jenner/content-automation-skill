# Fase 3 — Geração de clipes (Higgsfield) com teto de créditos — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar o storyboard do modo gerado em clipes de vídeo, sob o teto de créditos, com um gerador falso nos testes e um modo em que o *agente* executa as chamadas reais ao Higgsfield (cotar, confirmar o total, gerar, registrar), e montar os clipes em um vídeo 9:16.

**Architecture:** Igual às fases 1b e 2. Um `gen-plan.json` (derivado do storyboard) lista as cenas. `generate-clips.sh` cota cada cena (`budget.py quote`), exige a confirmação do total (`budget.py confirm <total>`) e só então gera. O gerador é uma porta: `fake` (testes) ou `mcp-agent`, em que o script imprime o *payload exato* de `generate_video` e o agente (skill) faz a chamada ao MCP; depois o resultado volta com `register`. Um manifesto (`clips-manifest.json`) liga cada cena ao arquivo, custo, job e hash.

**Tech Stack:** bash, python3 (stdlib), ffmpeg; `budget.py` (Fase 1b).

**Spec:** `docs/superpowers/specs/2026-10-16-clo-content-pipeline-design.md` (modo gerado, Higgsfield com teto) e `docs/validacao-contas-teste.md`.

## Fatos verificados em leitura (2026-10-17, nada foi gasto)
- `generate_video`: `params.model` obrigatório; `prompt`, `aspect_ratio` (`9:16`), `duration` (inteiro), `get_cost:true` (cota **sem criar job nem cobrar**), `count` (usar 1), `medias`, `folder_id`. `use_unlim` e `use_free_gens` só se o usuário pedir explicitamente: **nunca** são enviados por nós.
- `seedance_2_5` (modelo padrão para vídeo geral): `duration` de **4 a 30** (inteira), `resolution` `480p|720p|1080p` (padrão 720p), `generate_audio` (padrão true), `mode` `t2v` (padrão), `draft` (480p barato, finalizável em 7 dias), aspectos incluem `9:16`.
- `jobs_wait` devolve estados e **URLs dos resultados** (baixar a URL de forma automatizada ainda é **não verificado**).
- Uma timeout de transporte pode deixar o resultado da submissão desconhecido: **não reenviar automaticamente**; reaproveitar o `job_id` e conferir antes.

## Global Constraints
- As das fases anteriores (bash POSIX, python3 stdlib, nenhum teste chama serviço pago, texto ao usuário em PT-BR, ids/nomes seguros `^[A-Za-z0-9_-]{1,32}$`, caminhos relativos funcionam, saídas não sobrescritas sem `--force`, scripts novos com bit de execução no git, trava e escrita atômica para estado compartilhado, `</dev/null` nos laços, `set -e` fora de `if`).
- Nada gasta crédito sem **cotação + confirmação do total + teto**; o teto é do `budget.py`. Estouro de cotação é registrado e **interrompe o lote**. Variantes já pagas nunca são cobradas de novo.
- O gerador `mcp-agent` nunca envia `use_unlim`, `use_free_gens`, `preset_session_id` nem chama `get_katana_config`.
- Duração por cena: inteiro de 4 a 30 s (constantes marcadas "conferir com models_explore"). Máximo de 12 cenas por plano (limite do lote do Higgsfield).
- Vídeos gerados por IA devem ser declarados como tal ao publicar (`isAiGenerated`/`isAigc`); o manifesto marca `conteudo_ia: true`.

## Review Focus
- Cena de 3 s no storyboard (o exemplo do projeto) → ajustada para 4 s com aviso, nunca silenciosa.
- Prompt vazio, duração fora de 4–30, resolução desconhecida, cena duplicada, mais de 12 cenas → recusado.
- Duas execuções simultâneas do mesmo lote → nenhuma cena cobrada duas vezes.
- Plano alterado depois da confirmação (prompt, duração, resolução) → exige nova cotação/confirmação.
- Estouro numa cena do meio → registrado, lote para, cenas anteriores permanecem, retomada não cobra de novo.
- Arquivo de clip inválido/vazio/de outra duração registrado pelo agente → recusado, sem gastar.
- `register` de cena sem cotação confirmada, ou com custo acima da cotação → recusado/estouro registrado.
- Payload nunca contém `use_unlim`/`use_free_gens`, e `get_cost:true` na cotação vs `false` só depois de confirmado.

---

### Task 1: Plano de geração e conversor do storyboard

**Files:** Create `schemas/gen-plan.schema.json`, `scripts/storyboard_to_genplan.py`, `scripts/validate_genplan.py`, `tests/test_genplan.sh`

**Interfaces:**
- Produces: `{modelo:"seedance_2_5", aspecto:"9:16", resolucao:"480p|720p|1080p", audio:bool, cenas:[{id, prompt, duracao_s:int 4..30}]}`. `python3 scripts/storyboard_to_genplan.py <storyboard.json> [--resolucao 720p] [--audio]` imprime o gen-plan; exige `modo:"gerado"`; ids das cenas viram ids seguros; `duracao_s` é arredondada **para cima** a inteiro e elevada a 4 se menor, imprimindo `aviso: cena X ajustada de A para B s` em stderr. `python3 scripts/validate_genplan.py <gen-plan.json>` sai 0 só se: schema válido; 1–12 cenas; ids únicos (caixa ignorada); prompt não vazio (≤ 4000 caracteres); duração inteira 4–30; resolução na lista.

- [ ] **Step 1:** Testes: `test_converts_generated_storyboard`; `test_short_scene_is_raised_to_4_with_warning`; `test_recorded_storyboard_rejected`; `test_validator_rejects_bad_plans` (prompt vazio, 31 s, resolução 4k, 13 cenas, ids repetidos/inseguros); `test_default_resolution_and_audio_off`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 2: Gerador falso

**Files:** Create `scripts/generators/fake.sh`, `tests/test_generator_fake.sh`

**Interfaces:**
- Produces: `fake.sh quote <gen-plan> <id>` imprime o custo fictício (créditos por segundo: 480p=1, 720p=2, 1080p=4; mais 20 % se `audio`); `fake.sh run <gen-plan> <id> <saida.mp4>` cria um clipe 1080×1920 (ou proporcional à resolução) com a duração da cena e imprime o custo efetivo; `CLO_GEN_FAKE_OVERRUN=<id>` dobra o custo efetivo (somente testes). Nunca usa rede.

- [ ] **Step 1:** Testes: cota por resolução e áudio; clipe com a duração e proporção certas (`ffprobe`); estouro; id inseguro recusado; sem rede (nenhum `curl`/`wget` no script).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 3: `generate-clips.sh` — cotar, confirmar, gerar

**Files:** Create `scripts/generate-clips.sh`, `scripts/clips_manifest.py`, `tests/test_generate_clips.sh`

**Interfaces:**
- Consumes: Tasks 1–2, `budget.py` (`quote/confirm/check/spend/state`), `variant_info`-like leitura do plano.
- Produces: `generate-clips.sh <gen-plan> <dir> --budget <arq> --stage quote|run [--generator fake] [--force]`. Item do orçamento = `clip-<id>-<hash8 de prompt+modelo+duração+resolução+áudio+aspecto>`. `quote` cota cada cena (pula as já confirmadas/gastas) e mostra o total. `run` só roda cenas com cotação confirmada (checando todas antes de gerar), recota (grátis) e recusa se o preço subiu, pula cenas pagas que já têm arquivo ("já concluída"), para o lote no primeiro estouro (registrando o gasto efetivo), mantém as anteriores e atualiza o manifesto de forma atômica (`<dir>/clips-manifest.json`: cena, arquivo, sha256, custo, job_id, origem, `conteudo_ia:true`). `clips_manifest.py add|show` grava/lê o manifesto com trava.

- [ ] **Step 1:** Testes (gerador falso): cotar não gera nem gasta; `run` sem confirmação recusa e nada é gerado; fluxo feliz gasta o total e cria N clipes + manifesto; total acima do teto bloqueia o `confirm`; estouro registra, para o lote, mantém anteriores; retomada não cobra de novo; plano alterado depois de confirmar → "sem cotação confirmada"; saída existente exige `--force` antes de gastar; execuções simultâneas não cobram duas vezes a mesma cena; caminhos relativos e com espaço.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 4: Modo `mcp-agent` (payload e registro)

**Files:** Modify `scripts/generate-clips.sh`; Create `scripts/genpayload.py`, `tests/test_generate_payload.sh`

**Interfaces:**
- Produces: `generate-clips.sh <gen-plan> <dir> --generator mcp-agent --stage payload --scene <id> [--cost-only]` imprime o JSON `{"params": {"model","prompt","aspect_ratio","duration","resolution","generate_audio","count":1,"get_cost":true|false}}` (com `--cost-only` → `get_cost:true`). Nunca inclui `use_unlim`, `use_free_gens`, `preset_session_id` nem `medias`. `--stage register --scene <id> --job-id <uuid> --custo <n> --arquivo <caminho>` confere: cotação confirmada e não gasta; arquivo é vídeo legível (`ffprobe`) de duração ≥ a pedida −1 s; copia para `<dir>/clips/<id>.mp4`, grava `spend` (estouro registrado, código 3) e atualiza o manifesto (origem `mcp-agent`).

- [ ] **Step 1:** Testes: payload exato para `--cost-only` e para geração; ausência dos campos proibidos; `register` sem confirmação, com arquivo inválido, com duração curta demais e com custo acima da cotação (estouro) → comportamentos esperados; registro válido atualiza orçamento e manifesto.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 5: Montagem dos clipes

**Files:** Create `scripts/assemble-clips.sh`, `tests/test_assemble_clips.sh`

**Interfaces:**
- Consumes: `clips-manifest.json` (Task 3), `reframe-9x16.sh`, `normalize-audio.sh`.
- Produces: `assemble-clips.sh <gen-plan> <manifesto> <saida.mp4> [--force]` concatena os clipes **na ordem do plano** (falha se faltar clipe ou se o hash do arquivo não bater com o manifesto), normaliza o áudio quando existir, reenquadra para 1080×1920 e escreve a saída de forma atômica; sem áudio nos clipes, gera vídeo mudo sem erro.

- [ ] **Step 1:** Testes: ordem correta (duração total e marca de cor/posição), clipe ausente, hash alterado, clipes mudos, saída existente sem `--force`, caminhos com espaço.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 6: Skill `generate-clips` e orquestradora

**Files:** Create `skills/generate-clips/SKILL.md`; Modify `skills/content-pipeline/SKILL.md`, `docs/arquitetura.md`, `README.md`; Create `tests/test_generate_skills.sh`

**Interfaces:**
- Produces: a skill conduz: storyboard aprovado → gen-plan (avisos de duração) → perguntar resolução/áudio → teto (`budget.py init`) → cotar (agente chama `generate_video` com `get_cost:true`, uma cena por vez, via payload) → mostrar o **total** → só com o "aprovo" do usuário: `budget.py confirm <total>` → gerar cena a cena (nunca em paralelo sem necessidade), `jobs_wait`, baixar o resultado, `register` → montar. Declara que o fluxo real depende do agente e que a **baixa automatizada do resultado é não verificada**; `use_unlim`/`use_free_gens` nunca; timeout de submissão = não reenviar, conferir pelo `job_id`. A orquestradora troca o passo "geração ainda não implementada" por esta skill (mantendo a honestidade sobre o que não foi validado).

- [ ] **Step 1:** Testes: SKILL contém `budget.py`, `get_cost`, `register`, "aprovo", "não reenviar", "não verificado", `CLAUDE_PLUGIN_ROOT`, e **não** contém `use_unlim: true`; a orquestradora cita `generate-clips`.
- [ ] **Step 2–4:** Falhar, escrever, passar. **Step 5:** suíte completa + shellcheck; commit.

---

## Auto-revisão
- **Cobertura:** prompts por cena a partir do storyboard (T1), gerador falso (T2), teto/cotação/confirmação/estouro/retomada (T3), execução real pelo agente (T4), juntar cenas e 9:16 (T5), skill e honestidade (T6).
- **Fora de escopo declarado:** chamadas reais ao Higgsfield (exigem a autorização e o teto do usuário, na validação com conta), legendas/trilha/motion do modo gerado (Remotion, Fase 5), referências de imagem (`medias`), modos `video_edit`/`video_extension`, o campo `conteudo_ia` no `schedule-plan` (Fase 2b).
- **Consistência:** `gen-plan.json` (T1) → `fake.sh` (T2) e `genpayload.py` (T4) → `generate-clips.sh` (T3/T4) → `clips-manifest.json` → `assemble-clips.sh` (T5).
