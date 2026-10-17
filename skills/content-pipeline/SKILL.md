---
name: content-pipeline
description: Conduz a criação de um vídeo curto do Clo App do roteiro à edição (e, nas próximas fases, geração e agendamento), com pesquisa embasada, várias versões do mesmo bruto e aprovação humana. Use quando o usuário pedir para criar, produzir ou editar um vídeo/conteúdo.
---

# Pipeline de conteúdo em vídeo (CLO)

Esta é a skill que o usuário usa. Converse em português do Brasil, uma pergunta por vez.

```
pesquisa → roteiro/hook → [modo] → bruto → edição (editor + N vídeos) → agendamento → APROVAÇÃO HUMANA
                          ├─ gerado  → prompts por cena → clipes (geração)
                          └─ gravado → shot list → usuário grava → caminho do arquivo
```

## 1. Descubra o modo
Pergunte (ou deduza do pedido e confirme em uma frase): o vídeo será **gerado** (clipes criados por IA) ou **gravado** (o usuário grava)? Se o usuário já tem um vídeo gravado e só quer editar, vá direto ao passo 4 com o caminho do arquivo.

## 2. Pesquisa e roteiro
Use a skill `research-trends` (dados reais, com fontes) e depois `script-storyboard`. Não proponha roteiro sem `research.json` válido. O usuário aprova o roteiro antes de seguir.

## 3. Etapa do meio
- **Modo gravado:** entregue a shot list e espere o usuário gravar. Peça o **caminho do arquivo** no disco.
- **Modo gerado:** use a skill `generate-clips` (Higgsfield, cena a cena, sob um **teto de créditos** definido pelo usuário, com cotação, aprovação do total e registro de cada clipe). Ela monta os clipes em `video-gerado.mp4`. Avise que a **baixa automatizada** do resultado ainda não foi verificada com a conta real, e que as legendas e a trilha do modo gerado ainda não implementadas (a edição segue manual).

## 4. Edição: duas perguntas antes de começar
1. **Qual editor?**
   - `local` (padrão): a edição desta ferramenta (ffmpeg), sem custo.
   - `katana`: a edição dentro do Higgsfield, que consome créditos. O editor `katana` ainda não implementado nesta versão: diga isso e ofereça o `local`. Quando existir, ele só roda com **teto de gastos** definido pelo usuário, custo estimado antes e confirmação.
2. **Quantos vídeos finais?** De 1 a 5 (o máximo é 5, para qualquer editor). Um bruto pode virar vários vídeos: cada um mostra uma parte diferente do bruto, ou a mesma parte com uma edição diferente. Se o usuário pedir mais de 5, explique o limite e peça um número de 1 a 5.

Depois use a skill `edit-recorded` (modo gravado). Para o modo gerado, a edição das cenas geradas ainda não implementada nesta versão.

## 5. Agendamento e publicação
Use a skill `schedule-post`: legenda, hashtags, dias e horários, validação e **aprovação por post** (amarrada ao conteúdo exato). Os agendadores reais (MCP) ainda não implementados nesta versão: a entrega de verdade é o **pacote manual** (`export_package.sh`: vídeo, legenda, horário e passo a passo), que o usuário agenda no próprio Instagram/TikTok. O agendador `fake` serve só para ensaio e não agenda nada de verdade. **Nunca publique nem agende sem aprovação explícita do usuário.**

## Regras
- Aprovação humana é obrigatória: do roteiro, dos cortes criativos, **de cada variante** e, no futuro, de data/hora e legenda antes de agendar.
- Qualquer coisa que consuma crédito respeita o teto de gastos: estimar antes, mostrar o total e só seguir com confirmação.
- Nunca invente dado ou fonte; diga quando algo for hipótese.
- Se faltar dependência, rode `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"` e oriente a instalação.
