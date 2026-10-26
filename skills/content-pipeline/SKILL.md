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
Pergunte (ou deduza do pedido e confirme em uma frase): o vídeo será **gerado** (clipes criados por IA), **gravado** (o usuário grava) ou um **slideshow/carrossel** (o usuário envia fotos e só se organiza a ordem e o texto)? Se o usuário já tem um vídeo gravado e só quer editar, vá direto ao passo 4 com o caminho do arquivo.

**Slideshow/carrossel:** com fotos do usuário, use a skill `create-slideshow` (pesquisa, roteiro por slide em formato hook/app/CTA, várias versões reordenando as mesmas fotos, aprovação por variante, PNGs do carrossel nativo do Instagram / Modo Foto do TikTok, vídeo opcional; sem custo). Ela substitui os passos 1b, 3 e 4 (não há geração nem teto de créditos); depois vá ao passo 5.

## 1b. Teto de gastos (opcional)
Quase ninguém sabe quanto custa um clipe, então **antes de perguntar**, mostre a tabela de referência (qualidade x duração -> créditos e valor aproximado):
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/reference_table.py" --duracoes 5,10,15,30
```
Se o usuário quiser ver em reais, pergunte a **cotação do dólar** que ele usa e rode de novo com `--cotacao-dolar <valor>` (nunca invente a cotação). Explique que o valor em dinheiro é aproximado e que o preço exato é cotado com `get_cost` (sem cobrar nada) antes de gerar. Ajude a escolher com exemplos da tabela (por exemplo, um vídeo de 15 s a 720p). Os dados (`data/precos-higgsfield.json`) têm a data da consulta: se estiverem velhos, avise e confirme com uma cotação `get_cost`. Depois pergunte: "Quer definir um **teto de créditos** para esta produção? É opcional." O usuário escolhe um valor ou prefere **não ter teto** (`sem-teto`). Guarde a resposta e use-a em tudo que consome crédito (`generate-clips`, e o editor `katana` quando existir): ela vira o argumento de `budget.py init` (`<teto>` ou `sem-teto`).
- **Com teto:** nada passa dele; estouro é registrado e interrompe o lote.
- **Sem teto:** o custo continua sendo **estimado antes, mostrado como total e só segue com a confirmação do usuário**; apenas não há limite máximo. O usuário pode definir um teto depois (`budget.py raise`).
- O modo gravado com editor `local` não gasta crédito e não precisa dessa pergunta.

## 2. Pesquisa e roteiro
Use a skill `research-trends` (dados reais, com fontes) e depois `script-storyboard`. Não proponha roteiro sem `research.json` válido. O usuário aprova o roteiro antes de seguir.

## 3. Etapa do meio
- **Modo gravado:** entregue a shot list e espere o usuário gravar. Peça o **caminho do arquivo** no disco.
- **Modo gerado:** use a skill `generate-clips` (Higgsfield, cena a cena, sob um **teto de créditos** definido pelo usuário, com cotação, aprovação do total e registro de cada clipe). Ela monta os clipes em `video-gerado.mp4`. A geração e a baixa do clipe já foram validadas com a conta real (480p, uma cena); 720p/1080p e áudio gerado ainda não.

## 4. Edição: duas perguntas antes de começar
1. **Qual editor?**
   - `local` (padrão): a edição desta ferramenta (ffmpeg), sem custo.
   - `katana`: a edição autônoma dentro do Higgsfield, que **gasta créditos sozinha** (sem pedir confirmação no meio). Use a skill `edit-katana`: exige o "aceito" explícito do usuário, passa o teto opcional como limite (ou diz que não há limite) e registra o gasto. A baixa do resultado do Katana é não verificada com a conta real.
2. **Quantos vídeos finais?** De 1 a 5 (o máximo é 5, para qualquer editor). Um bruto pode virar vários vídeos: cada um mostra uma parte diferente do bruto, ou a mesma parte com uma edição diferente. Se o usuário pedir mais de 5, explique o limite e peça um número de 1 a 5.

Depois use a skill `edit-recorded` (modo gravado). No **modo gerado**, use a skill `edit-generated` (legendas por cena escritas a partir do roteiro e uma trilha sonora que o usuário fornece, tudo local e sem gastar crédito). No modo gerado, as variantes (de 1 a 5 vídeos finais, recombinando os clipes já gerados com outras cenas, legendas e trilha) estão na própria `edit-generated` (`run-gen-variants.sh`), sem gastar crédito, com aprovação por variante; clipes novos continuam sendo da `generate-clips`, com teto. O motion ainda não implementado nesta versão.

## 5. Agendamento e publicação
Use a skill `schedule-post`: legenda, hashtags, dias e horários, validação e **aprovação por post** (amarrada ao conteúdo exato). Os agendadores reais (MCP) ainda não implementados nesta versão: a entrega de verdade é o **pacote manual** (`export_package.sh`: vídeo, legenda, horário e passo a passo), que o usuário agenda no próprio Instagram/TikTok. O agendador `fake` serve só para ensaio e não agenda nada de verdade. **Nunca publique nem agende sem aprovação explícita do usuário.**

## Regras
- Aprovação humana é obrigatória: do roteiro, dos cortes criativos, **de cada variante** e, no futuro, de data/hora e legenda antes de agendar.
- Qualquer coisa que consuma crédito: estimar antes, mostrar o total e só seguir com confirmação; se o usuário definiu um teto (opcional), ele nunca é ultrapassado.
- Nunca invente dado ou fonte; diga quando algo for hipótese.
- Se faltar dependência, rode `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"` e oriente a instalação.
