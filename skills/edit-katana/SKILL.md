---
name: edit-katana
description: Edita as variantes aprovadas de um vídeo gravado com o Katana do Higgsfield (edição autônoma que gasta créditos por conta própria), respeitando o teto opcional do usuário e registrando o resultado e o gasto. Use só quando o usuário escolheu o editor katana no variants-plan.
---

# Edição com o Katana (Higgsfield)

Converse em português do Brasil, uma pergunta por vez. **Esta etapa gasta créditos de verdade e o Katana gasta sozinho:** ele não pede confirmação durante o trabalho e só cota depois de analisar o material. Por isso a proteção é feita **antes** (aceitação do usuário e limite) e **depois** (registro do gasto).

## O que o usuário precisa saber antes (diga com estas palavras)
- O Katana é uma edição autônoma do Higgsfield. Ele analisa o vídeo, planeja e gasta créditos **sem perguntar nada no meio do caminho**.
- Não existe cotação fechada antes de começar. O que o usuário controla é o **limite**.
- Se o usuário definiu um teto, ele vira o **limite de créditos** passado ao Katana (o que resta do teto). Se **não** definiu teto, o Katana define o próprio limite: é **sem limite fixo do usuário**.
- Uma alternativa de custo zero: o editor `local` (ffmpeg) faz cortes, legendas e áudio sem gastar nada.

## 1. Pré-requisitos
- `variants-plan.json` válido com `"editor": "katana"` e pelo menos uma variante `aprovada: true` (aprovação do usuário **por variante**; veja a skill `edit-recorded`).
- Orçamento criado no início do fluxo: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/budget.py" init "<budget.json>" <teto|sem-teto>` (o teto é opcional).
- O vídeo bruto no disco e o transcript (do `propose`), como no modo gravado.

## 2. Aceitação explícita
Mostre as variantes aprovadas e pergunte: "O Katana **gasta sozinho** até o limite de X créditos (ou **sem limite** fixo, se você não definiu teto). Você aceita?" **Só continue depois de um "aceito" claro**, e só para as variantes que o usuário listar. Uma aceitação não vale para outra sessão nem para variantes novas.

## 3. Briefing por variante
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/katana_brief.py" "<variants-plan.json>" <id> --budget "<budget.json>"
```
O JSON traz `fonte`, `trechos`, `brief`, `limite_creditos` (null quando não há teto) e o `aviso`. Rode **uma variante por vez** e confira o limite de novo antes de cada uma (o teto restante muda a cada gasto).

## 4. Rodar o Katana (feito por você, o agente)
1. Carregue as ferramentas do Higgsfield de uma vez e leia o fluxo com `get_workflow_instructions` (workflow `katana`). Envie o `fonte` com `media_upload` → PUT → `media_confirm`.
2. Passe o `brief` e o `limite_creditos` como limite numérico do trabalho. Sem teto, diga ao Katana que não há limite numérico do usuário.
3. **Não use** `use_unlim`, `use_free_gens` nem presets sem o usuário pedir. `get_katana_config` **cria uma sessão** (não é leitura): só use se for rodar um preset `/katana/...` que o usuário escolheu.
4. Acompanhe com `jobs_wait`. Se o Katana disser que não pôde concluir, **pare**, mostre o que foi gasto (`transactions`) e não tente de novo sem o usuário.
5. Baixe o vídeo final para o disco. A baixa de um clipe gerado já foi validada (`curl -L` da `result_url`), mas a do resultado do **Katana** é **não verificada** com a conta real. Se não conseguir baixar, peça ao usuário que baixe o arquivo do Higgsfield e informe o caminho.
6. Descubra o **gasto real** (diferença de `balance` antes e depois, ou `transactions`) e os `job_ids`.

## 5. Registrar
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/katana_register.sh" "<variants-plan.json>" <id> "<video-baixado>" "<pasta-de-saida>" --budget "<budget.json>" --gasto <creditos> --job-ids <id1,id2>
```
O script exige vídeo vertical 9:16 e entrega `final-<id>.mp4` mais um `final-<id>.katana.json`. Se o gasto passar do teto, ele **registra, mantém o vídeo e sai com erro**: pare o lote e pergunte ao usuário o que fazer (aumentar o teto com `budget.py raise`, ou parar).

## Regras
- Nunca invente dado ou resultado; diga o que não foi verificado.
- O Katana pode gerar partes do vídeo: se houver cenas geradas, declare **conteúdo de IA** ao publicar (veja `schedule-post`).
- Não publique nem agende nada aqui: o próximo passo é a skill `schedule-post`.
