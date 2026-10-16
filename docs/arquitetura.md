# Arquitetura

Plugin do Claude Code: skills (instruções para o Claude) + scripts (bash + ffmpeg, com python3 só da biblioteca padrão).

## Skills
| Skill | Papel |
|---|---|
| `content-pipeline` | Orquestradora; é a única que o usuário invoca |
| `research-trends` | Pesquisa na web com fontes → `research.json` |
| `script-storyboard` | Hook, roteiro, storyboard (gerado) ou shot list (gravado) |
| `edit-recorded` | Edição do vídeo gravado, com aprovação dos cortes |

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
