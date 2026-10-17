# Fase 3b — Edição do modo gerado (legendas e trilha) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sobre o vídeo montado do modo gerado (`assemble-clips.sh`), queimar legendas escritas por cena e adicionar uma trilha sonora, tudo local, sem gastar crédito, e entregar um vídeo final 1080×1920 com áudio normalizado.

**Architecture:** Um `captions-plan.json` (textos por cena, com tempos relativos à cena e aprovação do usuário) vira um `transcript.json` com tempos absolutos (usando as durações reais dos clipes do manifesto) e passa pelo `subtitles.sh` já existente (estilos `padrao|destaque|discreto`). A trilha é um arquivo de áudio **fornecido pelo usuário**, ajustado à duração do vídeo (corte com fade-out, ou repetição se for curta), misturado em volume mais baixo e normalizado (~-14 LUFS). `edit-generated.sh` orquestra os dois passos.

**Tech Stack:** bash, python3 (stdlib), ffmpeg; reaproveita `subtitles.sh`, `normalize-audio.sh`, `transcript_to_srt.py`.

**Spec:** `docs/superpowers/specs/2026-10-16-clo-content-pipeline-design.md` (modo gerado: "legenda, trilha, 9:16").

## Decisões do builder (marcadas como minhas; mudáveis)
- **Fonte do texto das legendas:** não existe fala nos clipes (gerados sem áudio por padrão), então o texto vem do **roteiro**: a skill propõe uma ou mais legendas por cena (texto curto, na tela) e o usuário aprova. Não há transcrição.
- **Fonte da trilha:** um **arquivo de áudio que o usuário fornece** (caminho local). Nada é baixado nem gerado (gerar áudio gastaria crédito) e a responsabilidade pela **licença** da música é do usuário; a skill avisa. Músicas em alta de cada rede costumam ser aplicadas no próprio app e não dá para automatizar.
- **Mistura:** trilha em volume relativo configurável (padrão -18 dB), fade-in 0,5 s e fade-out 1,5 s; se o vídeo já tiver áudio, a trilha entra por baixo (mistura simples, sem ducking automático nesta fase); depois, normalização para ~-14 LUFS.
- **Variantes (até 5 vídeos por bruto) no modo gerado:** fora desta fase (o `edit-recorded --variants` depende de áudio para detectar silêncio). Fica registrado como pendência.
- **Remotion/motion:** continua sendo a Fase 5, por último.

## Global Constraints
- As das fases anteriores (bash POSIX, python3 stdlib, nenhum teste chama serviço pago ou rede, texto ao usuário em PT-BR, ids/nomes seguros, caminhos relativos e com espaço, saídas não sobrescritas sem `--force`, escrita atômica, scripts novos com bit de execução no git, `</dev/null` nos laços, trap sem variável local).
- **Sem custo:** nenhum passo desta fase chama o Higgsfield nem outro serviço.
- Vídeo gerado por IA continua precisando ser declarado como tal ao publicar (já no manifesto: `conteudo_ia`).
- Legenda: no máximo 3 linhas de 42 caracteres por bloco (126 caracteres), no máximo 40 legendas por plano, duração mínima 0,8 s por legenda.

## Review Focus
- Legenda com tempo fora da cena, sobreposta na mesma cena, texto vazio, grande demais, cena inexistente → recusada antes de queimar.
- Legenda com acentos, aspas, `{...}` e `\N` (o libass interpreta como tag/quebra) → aparece como texto, sem sumir.
- Clipes com duração real diferente da planejada → as legendas seguem a duração REAL.
- Trilha mais curta/longa que o vídeo, arquivo que não é áudio, arquivo só com vídeo, volume fora dos limites, trilha silenciosa (loudnorm com `-inf`).
- Vídeo com e sem áudio original; mono e estéreo.
- Saída existente, caminhos com espaço/acento/relativos, falha no meio sem deixar resíduo.

---

### Task 1: Plano de legendas e conversão para transcript

**Files:** Create `schemas/captions-plan.schema.json`, `scripts/captions_to_transcript.py`, `tests/test_captions_plan.sh`

**Interfaces:**
- Produces: `captions-plan.json` = `{estilo:"padrao"|"destaque"|"discreto", cenas:[{cena:"<id>", legendas:[{texto, inicio_s?, fim_s?}]}]}` (tempos relativos ao início da cena; padrão `inicio_s=0.2` e `fim_s=duração−0.2`). `python3 scripts/captions_to_transcript.py <captions-plan> <gen-plan> <clips-manifest>` imprime um `transcript.json` (`{idioma:"pt", segmentos:[{inicio_s, fim_s, texto}]}`) com tempos **absolutos**, somando as durações reais (via `ffprobe`) dos clipes anteriores na ordem do plano. `--estilo` imprime só o estilo. Recusa: cena que não existe no gen-plan ou no manifesto, texto vazio ou com mais de 126 caracteres, `fim_s <= inicio_s` ou duração < 0,8 s, tempos fora da cena, legendas sobrepostas na mesma cena, mais de 40 legendas, estilo desconhecido.

- [ ] **Step 1:** Testes: `test_offsets_follow_the_real_clip_durations`; `test_default_timing_covers_the_scene`; `test_output_validates_as_transcript`; `test_invalid_captions_are_rejected` (cada regra); `test_special_characters_survive` (acentos, aspas, `{}`/`\N` preservados no JSON); `test_style_option`.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 2: Trilha sonora (`add-soundtrack.sh`)

**Files:** Create `scripts/add-soundtrack.sh`, `tests/test_soundtrack.sh`

**Interfaces:**
- Produces: `add-soundtrack.sh <video> <musica> <saida.mp4> [--volume-db -18] [--force]`. Trilha mais longa que o vídeo → cortada, com fade-out de 1,5 s terminando no fim do vídeo; mais curta → repetida em laço; fade-in de 0,5 s; volume relativo `--volume-db` entre -40 e 0; se o vídeo tem áudio, a trilha é misturada por baixo; saída normalizada (~-14 LUFS) com o vídeo copiado sem re-encode. Recusa: arquivo ausente, sem faixa de áudio, ilegível, trilha silenciosa (nada para normalizar), vídeo ilegível, saída existente sem `--force`.

- [ ] **Step 1:** Testes: vídeo mudo + trilha curta (laço, duração do vídeo ±0,15 s, tem áudio); trilha longa (cortada, fade-out audível: nível dos últimos 0,5 s ≥ 6 dB abaixo do meio); vídeo com áudio + trilha (1 faixa de áudio na saída, loudness ~-14 ±1,5); volume fora do intervalo; arquivo sem áudio / ilegível / silencioso; saída existente; caminhos com espaço e relativos.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 3: `edit-generated.sh` (legendas + trilha)

**Files:** Create `scripts/edit-generated.sh`, `tests/test_edit_generated.sh`

**Interfaces:**
- Consumes: Tasks 1–2, `subtitles.sh`, saídas de `assemble-clips.sh` e `generate-clips.sh` (gen-plan, manifesto).
- Produces: `edit-generated.sh <video-montado> <gen-plan> <manifesto> <saida.mp4> [--captions <captions-plan>] [--music <arquivo>] [--volume-db -18] [--force]`. Exige ao menos uma das duas opções. Ordem: valida tudo antes de processar; trilha → legendas (queima com o estilo do plano); gera `<saida>.srt` ao lado; saída 1080×1920; escrita atômica; falha no meio não deixa resíduo.

- [ ] **Step 1:** Testes (clipes de ffmpeg, sem rede): só legendas; só trilha; legendas + trilha; nenhuma opção; legenda inválida recusada sem criar saída; saída existente; duração final ≈ vídeo montado; legendas aparecem (o `.srt` tem os tempos esperados); caminhos relativos/espaços.
- [ ] **Step 2–4:** Falhar, implementar, passar. **Step 5:** Commit.

### Task 4: Skill `edit-generated` e orquestradora

**Files:** Create `skills/edit-generated/SKILL.md`, `tests/test_edit_generated_skills.sh`; Modify `skills/content-pipeline/SKILL.md`, `docs/arquitetura.md`

**Interfaces:**
- Produces: a skill conduz: vídeo montado → propor legendas por cena a partir do roteiro e da pesquisa (`research.json`), mostrar ao usuário, **só com "aprovo"** gravar `captions-plan.json` → perguntar se há trilha (arquivo do usuário, aviso de licença, volume) → `edit-generated.sh` → conferir o resultado → entrega. Declara o que não existe (variantes no modo gerado, motion/Remotion) e que **nenhum passo gasta crédito**. A orquestradora troca "edição do modo gerado ainda não implementada" por esta skill.

- [ ] **Step 1:** Testes: SKILL contém `captions-plan.json`, `edit-generated.sh`, "aprovo", "licença", `CLAUDE_PLUGIN_ROOT`, "não gasta crédito", "ainda não implementad" (variantes/motion); sem caminhos relativos; a orquestradora cita `edit-generated`.
- [ ] **Step 2–4:** Falhar, escrever, passar. **Step 5:** suíte completa + shellcheck; commit.

---

## Auto-revisão
- **Cobertura:** legendas do modo gerado a partir do roteiro (T1, T3, T4), trilha (T2, T3), 9:16 e loudness (T2, T3), aprovação humana (T4), sem custo (todas).
- **Fora de escopo declarado:** variantes no modo gerado, ducking automático, geração de música/narração (gastaria crédito), motion/Remotion (Fase 5), download de músicas.
- **Consistência:** `captions-plan.json` (T1) → `transcript.json` → `subtitles.sh --style` (T3); `add-soundtrack.sh` (T2) → `edit-generated.sh` (T3).
