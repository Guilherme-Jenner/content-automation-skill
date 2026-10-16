---
name: content-pipeline
description: Conduz a criação de um vídeo curto do Clo App do roteiro à edição (e, nas próximas fases, geração e agendamento), com pesquisa embasada e aprovação humana. Use quando o usuário pedir para criar, produzir ou editar um vídeo/conteúdo.
---

# Pipeline de conteúdo em vídeo (CLO)

Esta é a skill que o usuário usa. Converse em português do Brasil, uma pergunta por vez.

```
pesquisa → roteiro/hook → [modo] → edição → agendamento → APROVAÇÃO HUMANA
                          ├─ gerado  → prompts por cena → clipes (geração)
                          └─ gravado → shot list → usuário grava → caminho do arquivo
```

## 1. Descubra o modo
Pergunte (ou deduza do pedido e confirme em uma frase): o vídeo será **gerado** (clipes criados por IA) ou **gravado** (o usuário grava)? Se o usuário já tem um vídeo gravado e só quer editar, vá direto ao passo 4 com o caminho do arquivo.

## 2. Pesquisa e roteiro
Use a skill `research-trends` (dados reais, com fontes) e depois `script-storyboard`. Não proponha roteiro sem `research.json` válido. O usuário aprova o roteiro antes de seguir.

## 3. Etapa do meio
- **Modo gravado:** entregue a shot list e espere o usuário gravar. Peça o **caminho do arquivo** no disco.
- **Modo gerado:** a geração de clipes (Higgsfield, com teto de créditos) ainda não implementada nesta versão. Diga isso ao usuário e pare aqui, entregando o storyboard com os prompts por cena.

## 4. Edição
- **Modo gravado:** use a skill `edit-recorded` (corte de silêncios e cortes criativos aprovados, áudio, 9:16, legendas).
- **Modo gerado:** a edição das cenas geradas ainda não implementada nesta versão.

## 5. Agendamento e publicação
O agendamento ainda não implementado nesta versão. Entregue o vídeo final (`final.mp4`, `final.srt`) e, se o usuário quiser, sugira legenda do post e horários com base na pesquisa; ele agenda direto no Instagram/TikTok. **Nunca publique nem agende sem aprovação explícita do usuário.

## Regras
- Aprovação humana é obrigatória: do roteiro, dos cortes criativos e, no futuro, de data/hora e legenda antes de agendar.
- Nunca invente dado ou fonte; diga quando algo for hipótese.
- Se faltar dependência, rode `bash scripts/check-deps.sh` e oriente a instalação.
