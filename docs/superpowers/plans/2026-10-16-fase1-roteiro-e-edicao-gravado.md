# Fase 1 — Roteiro/Storyboard e Edição do Gravado — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar o esqueleto do plugin, as skills de roteiro/storyboard (modos gerado e gravado) e o pipeline de edição do vídeo gravado (até Whisper e legenda SRT), tudo testado sem serviço pago.

**Architecture:** Scripts bash/POSIX chamam `ffmpeg`; a lógica de parsing/validação fica em python3 (apenas biblioteca padrão). Dependências externas (transcritor) ficam atrás de uma porta com versão real e falsa, escolhida por variável de ambiente. Nenhum script de corte roda sem um plano de cortes aprovado em arquivo.

**Tech Stack:** bash, python3 (stdlib), ffmpeg/ffprobe, whisper.cpp (real), shellcheck.

**Spec:** `docs/superpowers/specs/2026-10-16-clo-content-pipeline-design.md`

## Escopo e fases seguintes (planos separados)
Este plano cobre só a Fase 1. Planos futuros, nesta ordem: (2) agendamento + agendador falso + aprovação por hash; (3) geração Higgsfield + teto + gerador falso; (4) empacotamento/marketplace para o Mac; (5) **Remotion: qualidade e acabamento visual, por último**. A pasta `remotion/` e o JSON de interface (Task 13) entram já nesta fase só como contrato, sem polimento.

## Global Constraints
- Scripts em `bash` POSIX-friendly, `shellcheck` limpo; sem dependência só de Windows (sem `cygpath`, PowerShell, `.exe` fixo).
- Lógica auxiliar em `python3` usando **somente biblioteca padrão**.
- Nenhum teste chama serviço pago ou rede. Transcrição nos testes: `CLO_TRANSCRIBER=fake`.
- Fixtures de vídeo geradas por `ffmpeg` (`lavfi`); nenhum binário versionado.
- Saída final: 1080×1920 (9:16), áudio ~-14 LUFS, fuso `America/Sao_Paulo` onde houver data.
- Tolerância de duração nos testes: ±0,1 s.
- Entrada de vídeo gravado sempre por **caminho de arquivo local**.
- Texto voltado ao usuário (SKILL.md, mensagens de erro, README) em português do Brasil.
- Cortes criativos exigem aprovação humana (arquivo de plano com `"approved": true`).

## Review Focus
- Caminho com espaços e acentos (`Meus Vídeos/take 1.mov`), comum no Mac e no Windows → funciona, sem quebrar aspas.
- Vídeo sem faixa de áudio → erro claro, não travar nem gerar saída vazia.
- Vídeo de celular com metadado de rotação (vertical gravado como horizontal rotacionado) → saída 9:16 correta.
- Vídeo inteiro silencioso ou muito curto (<1 s) → aviso claro, nenhum arquivo parcial.
- Plano de cortes com trechos sobrepostos, fora da duração ou invertidos → rejeitado antes de rodar.
- Legenda com acentos, aspas e caminho com `:` ou `'` (escape no filtro `subtitles` do ffmpeg) → queima sem erro.
- Saída já existente → não sobrescreve sem `--force`.

---

### Task 1: Esqueleto do repositório, runner de testes e checagem de dependências

**Files:**
- Create: `.gitignore`, `README.md`, `.claude-plugin/plugin.json`, `tests/run.sh`, `tests/lib/assert.sh`, `scripts/lib/common.sh`, `scripts/check-deps.sh`, `tests/test_check_deps.sh`

**Interfaces:**
- Produces: `tests/run.sh [padrão]` executa `tests/test_*.sh` e sai ≠0 se algum falhar. `tests/lib/assert.sh`: `assert_eq expected actual msg`, `assert_file_exists path`, `assert_fails cmd...`, `assert_near expected actual tol msg`. `scripts/lib/common.sh`: `die msg` (stderr em PT-BR, exit 1), `need_cmd name hint`, `tmpdir`. `scripts/check-deps.sh` lista `ffmpeg`, `ffprobe`, `python3` (obrigatórios) e `whisper-cli` (opcional) e sai ≠0 se faltar obrigatório, com dica `brew install ...`.

- [ ] **Step 1:** `git init`; escrever `tests/test_check_deps.sh` (nome `test_reports_missing_ffmpeg`): com `PATH` sem ffmpeg, `check-deps.sh` falha e a saída contém `brew install ffmpeg`.
- [ ] **Step 2:** Rodar `bash tests/run.sh check_deps` — Esperado: FAIL (script inexistente).
- [ ] **Step 3:** Implementar runner, asserts, `common.sh` e `check-deps.sh`; `plugin.json` mínimo (`name: clo-content-pipeline`).
- [ ] **Step 4:** Rodar `bash tests/run.sh` — Esperado: PASS. Rodar `shellcheck scripts/*.sh scripts/lib/*.sh tests/*.sh`.
- [ ] **Step 5:** Commit `chore: esqueleto do plugin e runner de testes`.

### Task 2: Gerador de fixtures

**Files:** Create `tests/fixtures/make.sh`, `tests/test_fixtures.sh`

**Interfaces:**
- Consumes: `need_cmd`, asserts (Task 1).
- Produces: `tests/fixtures/make.sh <dir>` cria em `<dir>`: `tone_silence_tone.mp4` (tom 2 s + silêncio 1,5 s + tom 3 s, 1920×1080, com áudio), `no_silence.mp4` (4 s), `no_audio.mp4` (3 s, sem áudio), `vertical.mp4` (1080×1920, 3 s), `rotated.mp4` (horizontal com metadado de rotação 90), `spaced name é.mp4` (cópia com espaço/acento), `corrupt.mp4` (bytes aleatórios).

- [ ] **Step 1:** Teste `test_fixture_durations`: `ffprobe` de `tone_silence_tone.mp4` ≈ 6,5 s (±0,1); `no_audio.mp4` sem stream de áudio; `corrupt.mp4` faz `ffprobe` falhar.
- [ ] **Step 2:** Rodar e ver falhar. **Step 3:** Implementar `make.sh` com `lavfi` (`sine`, `anullsrc`, `testsrc`, concat). **Step 4:** Rodar e ver passar. **Step 5:** Commit.

### Task 3: Validador de JSON e schemas

**Files:** Create `scripts/validate_json.py`, `schemas/storyboard.schema.json`, `schemas/shot-list.schema.json`, `schemas/cut-plan.schema.json`, `schemas/transcript.schema.json`, `tests/test_validate_json.sh`, `tests/data/` (exemplos válidos e inválidos)

**Interfaces:**
- Produces: `python3 scripts/validate_json.py <schema> <arquivo>` → exit 0 se válido; senão exit 1 com mensagem PT-BR apontando o campo (`cenas[2].duracao_s: esperado número > 0`). Suporta apenas: `type`, `required`, `properties`, `items`, `enum`, `minimum`, `exclusiveMinimum`, `minItems`.
- Formatos: **storyboard** `{titulo, duracao_alvo_s, modo: "gerado"|"gravado", cenas:[{id, descricao, duracao_s, prompt?}]}`; **shot-list** `{titulo, takes:[{id, enquadramento, fala, duracao_s}]}`; **cut-plan** `{video, duracao_s, approved: bool, cortes:[{inicio_s, fim_s, motivo}]}` (cortes = trechos **removidos**); **transcript** `{idioma, segmentos:[{inicio_s, fim_s, texto}]}`.

- [ ] **Step 1:** Testes: `test_valid_storyboard_passes`, `test_missing_field_names_the_path`, `test_negative_duration_rejected`, `test_cut_plan_requires_approved_field`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 4: Skill `script-storyboard` (modos gerado e gravado)

**Files:** Create `skills/script-storyboard/SKILL.md`, `scripts/check_durations.py`, `tests/data/storyboard_gerado.json`, `tests/data/shot_list_gravado.json`, `tests/test_storyboard.sh`

**Interfaces:**
- Consumes: schemas da Task 3.
- Produces: `python3 scripts/check_durations.py <arquivo.json>` → exit 0 se soma das durações de cenas/takes difere do `duracao_alvo_s` em ≤ 10 %; senão exit 1. A skill instrui o Claude a: perguntar tema, público (Clo App), duração-alvo e modo; gerar hook (primeiros 3 s), roteiro e o JSON validado; no modo gravado, produzir shot list (enquadramento, fala exata, duração) e pedir o **caminho do arquivo** depois da gravação.

- [ ] **Step 1:** Testes: exemplos de `tests/data` passam em `validate_json` e `check_durations`; `test_duration_mismatch_fails` (soma 20 s para alvo 30 s → falha); `test_skill_declares_both_modes` (SKILL.md contém frontmatter `name`/`description` e as palavras `gerado` e `gravado`).
- [ ] **Step 2–4:** Falhar, escrever SKILL.md (PT-BR) e script, passar. **Step 5:** Commit.

### Task 5: Detecção de silêncio → proposta de plano de cortes

**Files:** Create `scripts/silence-detect.sh`, `scripts/silence_to_cutplan.py`, `tests/test_silence_detect.sh`

**Interfaces:**
- Consumes: `probe_duration` e `require_audio` (adicionar a `common.sh`: `probe_duration <arquivo>` imprime segundos; `require_audio <arquivo>` morre com `o vídeo não tem faixa de áudio` se não houver).
- Produces: `scripts/silence-detect.sh <video> <saida.json> [--min-silence 0.6] [--noise -35dB] [--pad 0.15]` grava um cut-plan com `approved: false`, um corte por silêncio ≥ min, encolhido por `--pad` em cada borda. `silence_to_cutplan.py` lê a saída do `silencedetect` do ffmpeg (stdin) e emite o JSON.

- [ ] **Step 1:** Testes: `test_detects_single_silence` (em `tone_silence_tone.mp4`, 1 corte com início ≈2,0+pad e fim ≈3,5−pad); `test_no_silence_gives_empty_cuts`; `test_no_audio_errors_clearly`; `test_all_silent_warns_and_writes_nothing`; `test_spaced_accented_path_works`; `test_corrupt_file_errors_without_output`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 6: Aplicar cortes (somente com plano aprovado)

**Files:** Create `scripts/apply-cuts.sh`, `scripts/validate_cutplan.py`, `tests/test_apply_cuts.sh`

**Interfaces:**
- Consumes: `probe_duration`, `validate_json.py` (Task 3).
- Produces: `scripts/apply-cuts.sh <video> <cut-plan.json> <saida.mp4> [--force]`. Recusa se `approved != true`, se saída existe sem `--force`, ou se `validate_cutplan.py` achar cortes sobrepostos, invertidos, fora de `[0, duracao_s]`. Mantém áudio e vídeo sincronizados (re-encode, não `-c copy`). Escreve em arquivo temporário e só então move para a saída (sem resíduo parcial).

- [ ] **Step 1:** Testes: `test_refuses_unapproved_plan`; `test_applies_cut_duration` (6,5 s − corte de 1,2 s ≈ 5,3 s ±0,1); `test_empty_cuts_keeps_duration`; `test_overlapping_cuts_rejected`; `test_cut_outside_duration_rejected`; `test_refuses_overwrite_without_force`; `test_no_partial_output_on_failure`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 7: Porta de transcrição (real e falsa)

**Files:** Create `scripts/transcribe.sh`, `tests/fakes/transcribe_fake.sh`, `tests/data/transcript_fake.json`, `tests/test_transcribe.sh`

**Interfaces:**
- Produces: `scripts/transcribe.sh <video> <saida.json> [--lang pt]`. Com `CLO_TRANSCRIBER=fake` copia `tests/data/transcript_fake.json`; caso contrário extrai áudio 16 kHz mono com ffmpeg e chama `whisper-cli` (modelo em `$CLO_WHISPER_MODEL`, padrão `~/.cache/clo/ggml-small.bin`), convertendo a saída para o formato **transcript**. Falta de `whisper-cli` ou modelo → erro com instrução `brew install whisper-cpp`.

- [ ] **Step 1:** Testes: `test_fake_output_matches_schema`; `test_real_mode_without_whisper_gives_install_hint` (PATH sem `whisper-cli`).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.
- [ ] **Step 6 (manual, fora do CI):** `docs/testes-manuais.md` descreve como rodar com Whisper real e áudio em PT-BR, e o que conferir.

### Task 8: Legendas SRT e queima no vídeo

**Files:** Create `scripts/subtitles.sh`, `scripts/transcript_to_srt.py`, `tests/test_subtitles.sh`

**Interfaces:**
- Consumes: transcript (Task 3/7).
- Produces: `python3 scripts/transcript_to_srt.py <transcript.json>` imprime SRT (numeração sequencial, `HH:MM:SS,mmm`, quebra de linha em ≤ 42 caracteres, segmentos ordenados, vazios descartados, tempos limitados à duração). `scripts/subtitles.sh <video> <transcript.json> <saida.mp4> [--srt-only]` gera o `.srt` ao lado e, sem `--srt-only`, queima via filtro `subtitles` com escape de caminho (`:`, `'`, `\`, espaços).

- [ ] **Step 1:** Testes: `test_srt_format_and_order`; `test_srt_wraps_long_lines`; `test_srt_keeps_accents_and_quotes`; `test_empty_segments_dropped`; `test_burn_in_with_special_path` (saída tem mesma duração ±0,1 e vídeo válido).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 9: Normalização de áudio

**Files:** Create `scripts/normalize-audio.sh`, `tests/test_normalize_audio.sh`

**Interfaces:**
- Produces: `scripts/normalize-audio.sh <video> <saida.mp4>`: `loudnorm` em duas passagens para I=-14, TP=-1.5, LRA=11; vídeo copiado sem re-encode. Falha com `require_audio` se não houver áudio.

- [ ] **Step 1:** Teste `test_loudness_near_target`: medir a saída com `ffmpeg -af loudnorm=print_format=json` e verificar `input_i` em -14 ±1,5; `test_no_audio_errors_clearly`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 10: Reenquadramento 9:16

**Files:** Create `scripts/reframe-9x16.sh`, `tests/test_reframe.sh`

**Interfaces:**
- Produces: `scripts/reframe-9x16.sh <video> <saida.mp4> [--mode crop|blur]`. Saída 1080×1920 sem esticar: `crop` centraliza e corta; `blur` (padrão para horizontal) coloca o vídeo original sobre fundo desfocado. Respeita metadado de rotação (autorotate do ffmpeg). Vertical já em 9:16 só escala.

- [ ] **Step 1:** Testes: `test_horizontal_to_1080x1920`; `test_vertical_to_1080x1920`; `test_rotated_input_to_1080x1920`; `test_aspect_not_stretched` (modo `crop`: razão da região central preservada, checar por amostra de frame com `ffprobe` dimensões e `cropdetect`).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 11: Skill `edit-recorded` e orquestração de ponta a ponta

**Files:** Create `scripts/edit-recorded.sh`, `skills/edit-recorded/SKILL.md`, `tests/test_edit_recorded_e2e.sh`

**Interfaces:**
- Consumes: Tasks 5–10.
- Produces: `scripts/edit-recorded.sh <video> <diretorio_saida> --stage propose|apply`. `propose`: transcreve e gera `cut-plan.json` (`approved:false`) + `transcript.json`, imprime resumo PT-BR dos cortes. `apply`: exige plano aprovado e executa cortes → áudio → 9:16 → legenda, produzindo `final.mp4` e `final.srt`. SKILL.md instrui o Claude a: pedir o caminho do arquivo, rodar `propose`, **mostrar os cortes ao usuário**, propor cortes criativos adicionais (takes repetidos, trechos redundantes) editando o plano, só marcar `approved:true` após confirmação explícita, e então rodar `apply`.

- [ ] **Step 1:** Testes (com `CLO_TRANSCRIBER=fake`): `test_propose_creates_unapproved_plan`; `test_apply_without_approval_fails`; `test_full_pipeline_outputs` (`final.mp4` 1080×1920, duração ≈ original − cortes ±0,1, LUFS ≈ -14, `final.srt` existe); `test_skill_requires_explicit_approval` (SKILL.md contém o gate).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 12: Skill orquestradora (fase 1) e documentação

**Files:** Create `skills/content-pipeline/SKILL.md`, `docs/arquitetura.md`, `docs/guia-mac-socio.md`; Modify `README.md`, `.claude-plugin/plugin.json`

**Interfaces:**
- Produces: a orquestradora pergunta (ou deduz) o modo; chama `script-storyboard`; no modo gravado segue para `edit-recorded`; para etapas ainda não implementadas (geração, agendamento) informa que estão pendentes e para ali, sem inventar. O guia do Mac lista `brew install ffmpeg whisper-cpp shellcheck` e como baixar o modelo.

- [ ] **Step 1:** Teste `test_skills_have_valid_frontmatter`: todo `skills/*/SKILL.md` tem `name` igual ao nome da pasta e `description` não vazia; `plugin.json` é JSON válido.
- [ ] **Step 2–4:** Falhar, escrever, passar. **Step 5:** Rodar `bash tests/run.sh` completo + `shellcheck`; commit.

### Task 13: Contrato com o Remotion (sem polimento)

**Files:** Create `remotion/README.md`, `schemas/remotion-input.schema.json`, `scripts/to_remotion_input.py`, `tests/test_remotion_input.sh`

**Interfaces:**
- Produces: `python3 scripts/to_remotion_input.py <transcript.json> <video> > input.json` com `{video, largura:1080, altura:1920, fps, palavras:[{texto, inicio_s, fim_s}], estilo:"padrao"}` (palavras derivadas dos segmentos, tempo distribuído proporcionalmente ao tamanho). `remotion/README.md` registra que visual e qualidade são a **Fase 5**.

- [ ] **Step 1:** Testes: saída valida no schema; `test_words_cover_segment_time_without_overlap`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 14: Pesquisa embasada (research-trends) e brief de edição — *executar antes da Task 11*

**Files:** Create `schemas/research.schema.json`, `scripts/check_research.py`, `skills/research-trends/SKILL.md`, `tests/data/research_valid.json`, `tests/data/research_no_source.json`, `tests/test_research.sh`; Modify `skills/script-storyboard/SKILL.md` (T4) e `skills/edit-recorded/SKILL.md` (T11)

**Interfaces:**
- Produces: formato **research** `{proposta, plataforma, data_pesquisa, achados:[{afirmacao, tipo:"fato"|"hipotese", fonte_url?, fonte_titulo?, data_acesso?, aplicacao}]}`. `python3 scripts/check_research.py <research.json>` sai 0 só se: valida no schema; todo achado com `tipo:"fato"` tem `fonte_url` http(s), `fonte_titulo` e `data_acesso`; há ao menos 3 achados e ao menos 1 fato; todo achado tem `aplicacao`. Erro em PT-BR aponta o achado (`achados[1]: fato sem fonte_url`).
- A skill `research-trends` instrui: entender a ideia/proposta do vídeo (perguntar se faltar), pesquisar na web (WebSearch/WebFetch) retenção, hooks, ritmo de corte, legendas, duração e tendências do nicho/plataforma; gravar `research.json`; rodar `check_research.py`; só então apresentar. Se a busca falhar ou não achar fonte, **dizer isso** e marcar como hipótese; nunca inventar fonte.
- `script-storyboard` passa a exigir `research.json` válido antes de propor hook/roteiro e a citar o achado que justifica cada escolha. `edit-recorded` passa a exigir um **brief de edição** (ritmo, cortes, legendas, zoom, trilha) ligado aos achados antes de propor cortes criativos; tudo segue sujeito à aprovação do usuário.

- [ ] **Step 1:** Testes: `test_valid_research_passes`; `test_fact_without_source_rejected` (mensagem cita `achados[1]` e `fonte_url`); `test_too_few_findings_rejected`; `test_hypothesis_may_lack_source`; `test_skills_require_research` (SKILL.md de `research-trends` existe com frontmatter e menciona `check_research.py`; os de `script-storyboard` e `edit-recorded` mencionam `research.json`).
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

---

## Auto-revisão
- **Cobertura da spec:** estrutura (T1, T12), schemas (T3), roteiro/shot list dois modos (T4), edição do gravado completa (T5–T11), Whisper por porta + fake (T7), aprovação humana dos cortes (T6, T11), Remotion como contrato (T13), portabilidade/shellcheck (T1, T12). Fora desta fase por decisão: agendamento, Higgsfield, empacotamento e Remotion visual.
- **Pendente do ambiente:** instalar `ffmpeg` e `shellcheck` no Windows antes da Task 2; testes reais no Mac ficam como verificação manual da Task 12.
- **Consistência de nomes:** `cut-plan` (`cortes` = trechos removidos), `transcript` (`segmentos`), `probe_duration`, `require_audio` usados de forma igual nas tasks 5, 6, 9.
