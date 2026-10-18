# Arquitetura

Plugin do Claude Code: skills (instruções para o Claude) + scripts (bash + ffmpeg, com python3 só da biblioteca padrão).

## Skills
| Skill | Papel |
|---|---|
| `content-pipeline` | Orquestradora; é a única que o usuário invoca |
| `research-trends` | Pesquisa na web com fontes → `research.json` |
| `script-storyboard` | Hook, roteiro, storyboard (gerado) ou shot list (gravado) |
| `edit-recorded` | Edição do vídeo gravado, com aprovação dos cortes e variantes |
| `edit-generated` | Modo gerado: legendas por cena (do roteiro) e trilha do usuário sobre o vídeo montado, sem custo |
| `generate-clips` | Modo gerado: cotar, aprovar o total, gerar cena a cena sob teto e montar os clipes |
| `schedule-post` | Legenda, horários e aprovação por hash; entrega pelo pacote manual |

Fases seguintes: agendador por MCP, validação da geração real e da baixa dos resultados, motion no modo gerado, empacotamento para o Mac e, por último, o polimento visual com Remotion.

## Scripts (cada um testável sozinho)
`silence-detect.sh` → `apply-cuts.sh` (só com plano `approved:true`) → `normalize-audio.sh` → `reframe-9x16.sh` → `subtitles.sh`; `transcribe.sh` é a porta do Whisper (real ou falsa); `edit-recorded.sh` orquestra os estágios `propose` e `apply`; `retime_transcript.py` ajusta as legendas à linha do tempo cortada.

## Contratos (JSON)
`schemas/`: storyboard, shot-list, cut-plan, transcript, research. Validação por `validate_json.py` (subconjunto de JSON Schema, sem dependências).

## Decisões
- Aprovação humana é verificada por arquivo, não por conversa: sem `approved:true`, o corte não roda.
- Serviços externos ficam atrás de uma porta com versão falsa; nenhum teste chama serviço pago.
- Pesquisa: afirmação sem fonte vira hipótese (`check_research.py`).
- Windows é ambiente de desenvolvimento; o destino é Mac. Para rodar os testes: `bash tests/run.sh`.

## Agendamento (Fase 2)
`validate_schedule.py` → `propose_slots.py` (cadência) → `approval.py approve|verify` (hash de vídeo, legenda, hashtags, perfis e horário) → `schedule.sh` (simula por padrão; `--confirm` com aprovação válida; idempotente via `schedule_log.py`) com o agendador `fake`. Agendadores reais por MCP ainda não existem; o plano B é `export_package.sh`. Fuso fixo `-03:00` (Brasil sem horário de verão desde 2019).

## Geração de clipes (Fase 3)
`storyboard_to_genplan.py` → `gen-plan.json` (cenas de 4 a 30 s, `seedance_2_5`, 9:16) → `generate-clips.sh`: com o gerador `fake` (testes) cota/confirma/gera sob o teto do `budget.py`; com o gerador `mcp-agent` o script só monta o **payload exato** de `generate_video` e **registra** o clipe baixado, porque a chamada ao Higgsfield é feita pelo agente. `clips-manifest.json` liga cena, arquivo, hash, custo e job; `assemble-clips.sh` une os clipes na ordem do plano. Estouro de cotação é registrado e interrompe o lote; cena paga nunca é cobrada de novo.

## Edição do modo gerado (Fase 3b)
`captions-plan.json` (textos por cena, tempos relativos, aprovados pelo usuário) → `captions_to_transcript.py` (tempos absolutos com a duração REAL dos clipes) → `subtitles.sh --style`. A trilha é um arquivo do usuário: `add-soundtrack.sh` corta/repete, aplica fades e volume e normaliza (~-14 LUFS). `edit-generated.sh` valida tudo antes de processar e entrega atomicamente `final.mp4` (1080x1920) e `final.srt`. Texto entre chaves é escapado só na cópia de queima (o libass trataria `{...}` como código de estilo).

## Variantes do modo gerado (Fase 3c)
`gen-variants-plan.json` (1 a 5 variantes; cada uma com cenas na ordem escolhida, legendas, estilo e trilha opcional; `aprovada` por variante) → `validate_gen_variants.py` (ids seguros, cenas existentes, gancho = primeira legenda e diferente entre variantes, variantes idênticas recusadas) → `gen_variant_info.py` deriva um gen-plan por variante (mesmos prompts, logo mesma chave de orçamento e mesma verificação de hash do manifesto) → `run-gen-variants.sh`: valida tudo antes de produzir, depois `assemble-clips.sh` + `edit-generated.sh` por variante, entregando `final-<id>.mp4/.srt`. Custo zero; nunca toca no orçamento.

## Editor Katana real (agente) e teto opcional
O Katana (Higgsfield) é um fluxo **autônomo**: analisa o material e gasta créditos por conta própria, sem confirmação, e só cota depois da análise. Por isso o adaptador real não é um script de cotação: `katana_brief.py` monta o briefing (fonte, trechos, limite de créditos) para o agente; o agente roda o Katana (skill `edit-katana`, com o "aceito" explícito do usuário) e `katana_register.sh` valida o vídeo (9:16), entrega `final-<id>.mp4` e registra o gasto efetivo com `budget.py externo` (gasto acima do teto é registrado, o vídeo é mantido e o lote para). O **teto de gastos é opcional** (`budget.py init <arquivo> <teto|sem-teto>`): sem teto, a cotação e a confirmação do total continuam valendo nos fluxos que cotam (geração de clipes), e o Katana define o próprio limite.
