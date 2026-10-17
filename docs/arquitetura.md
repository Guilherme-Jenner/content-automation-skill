# Arquitetura

Plugin do Claude Code: skills (instruções para o Claude) + scripts (bash + ffmpeg, com python3 só da biblioteca padrão).

## Skills
| Skill | Papel |
|---|---|
| `content-pipeline` | Orquestradora; é a única que o usuário invoca |
| `research-trends` | Pesquisa na web com fontes → `research.json` |
| `script-storyboard` | Hook, roteiro, storyboard (gerado) ou shot list (gravado) |
| `edit-recorded` | Edição do vídeo gravado, com aprovação dos cortes e variantes |
| `generate-clips` | Modo gerado: cotar, aprovar o total, gerar cena a cena sob teto e montar os clipes |
| `schedule-post` | Legenda, horários e aprovação por hash; entrega pelo pacote manual |

Fases seguintes: `edit-generated`, `generate-clips` (Higgsfield + teto), `schedule-post` (aprovação por hash), e por último o polimento visual com Remotion.

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
