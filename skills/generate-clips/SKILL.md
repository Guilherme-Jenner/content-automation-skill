---
name: generate-clips
description: Gera os clipes de um storyboard do modo gerado no Higgsfield, cena a cena, sob um teto de créditos, e monta os clipes em um vídeo vertical. Use depois que o storyboard estiver aprovado e o usuário quiser gerar o vídeo.
---

# Geração de clipes (Higgsfield) com teto de créditos

Converse em português do Brasil, uma pergunta por vez. **Nada consome crédito sem cotação, aprovação do total e teto.** Aqui quem chama o Higgsfield é você (o agente); os scripts montam o payload exato e registram o resultado.

## Validado com a conta real (2026-10-18)
Teste feito com 1 clipe de 5 s, 480p, 9:16, sem áudio (15 créditos, plano Plus):
- O payload de cotação e o de geração funcionam exatamente como o script os emite. `get_cost` devolve `{"cost":{"credits":N,"credits_exact":N}}` sem criar job nem cobrar.
- `generate_video` devolve `results[0].id` (um UUID, o `job_id`) com `status: pending`. `jobs_wait` (cada espera dura até 15 s; um clipe de 5 s em 480p levou cerca de 1,5 min) mostra `in_progress` e depois `completed` com `result_url`. O campo `type` vem como "image" enquanto o job roda e vira "video" no fim: ignore.
- A **baixa** é um `curl -L` simples da `result_url` (CDN do Higgsfield, HTTP 200, sem autenticação): mp4 h264 de 480x854 a 24 fps.
- O **custo efetivo** é a diferença do `balance` antes e depois: deu exatamente 15, igual à cotação.
- `generate-clips.sh --stage register` **copia** o arquivo para `clips/<id>.mp4` e recusa se já existir: baixe para **outro caminho** (por exemplo `baixado-<id>.mp4`), nunca direto para `clips/`.

## O que ainda não está verificado (diga ao usuário)
- Gerações em 720p/1080p, com áudio gerado, várias cenas em lote e a retomada depois de timeout.
- O Katana e o `use_unlim` (nunca usados).
- O custo efetivo só é conhecido depois da geração; veja a regra no passo 6.
- Os limites de duração (4 a 30 s inteiros no `seedance_2_5`) vêm de `models_explore`; confira sempre com `get_cost` antes de gerar.

## 1. Entradas
Storyboard do modo gerado já aprovado (`storyboard.json`, com `prompt` em todas as cenas) e `research.json`. Sem storyboard aprovado, volte à skill `script-storyboard`.

## 2. Plano de geração
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/storyboard_to_genplan.py" "<storyboard.json>" --resolucao 720p > "<gen-plan.json>"
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_genplan.py" "<gen-plan.json>"
```
- **Mostre ao usuário todo aviso de duração** (por exemplo, uma cena de 3 s sobe para 4 s, o mínimo do modelo): isso muda a duração total do vídeo.
- Pergunte a **resolução** (`480p` é a mais barata e serve para teste; `720p` é o padrão; `1080p` é a mais cara) e se quer áudio gerado (desligado por padrão; a narração e a trilha entram depois).

## 3. Teto de créditos
O teto é **opcional**. Se o usuário ainda não viu quanto custa um clipe, mostre antes a tabela de referência (`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/reference_table.py"`; reais só com a cotação do dólar que ele informar). Use a escolha que o usuário fez ao iniciar o fluxo (ou pergunte agora: um valor máximo de créditos, ou `sem-teto`). Crie o orçamento (uma vez); sem teto, cotação, total e confirmação continuam valendo, só não há limite máximo:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/budget.py" init "<budget.json>" <teto|sem-teto>
```
Se quiser mostrar o saldo da conta, use `balance` (somente leitura).

## 4. Cotar (não gasta crédito)
Para **cada** cena, uma de cada vez:
1. Gere o payload de cotação e envie **sem alterar nada** à ferramenta `generate_video`:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/generate-clips.sh" "<gen-plan.json>" "<pasta de trabalho>" --generator mcp-agent --stage payload --scene <id> --cost-only
   ```
   Esse payload tem `get_cost: true`: a ferramenta devolve o custo **sem criar job e sem cobrar**.
2. Registre o número devolvido:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/generate-clips.sh" "<gen-plan.json>" "<pasta de trabalho>" --generator mcp-agent --stage register-quote --scene <id> --custo <número> --budget "<budget.json>"
   ```

## 5. Aprovação do total (obrigatória)
Mostre ao usuário o **total cotado** (a linha `total cotado` do orçamento), o custo por cena, o teto e o saldo. Pergunte se pode seguir. **Só depois de uma aprovação explícita (por exemplo "aprovo")**, confirme exatamente o total que ele viu:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/budget.py" confirm "<budget.json>" <total cotado>
```
Se o total passar do teto, o comando recusa: ajuste o plano (menos cenas, resolução menor) e cote de novo. Se o plano mudar depois da confirmação, a cotação deixa de valer.

## 6. Gerar, uma cena por vez
Sem execução em paralelo, a menos que o usuário peça e o teto comporte. Para cada cena:
1. Payload de geração (só sai se a cotação estiver confirmada):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/generate-clips.sh" "<gen-plan.json>" "<pasta de trabalho>" --generator mcp-agent --stage payload --scene <id> --budget "<budget.json>"
   ```
   Envie o JSON **sem alterar nada** a `generate_video` e guarde o `job_id`. O payload de geração de uma cena **sai uma única vez** (o orçamento marca a cena como emitida): um segundo envio poderia criar e cobrar um segundo job.
2. **Se a chamada der timeout, não reenvie**: o resultado da submissão é desconhecido. Reaproveite o `job_id` ou confira o job antes de qualquer nova tentativa. Só se tiver conferido que nenhum job foi criado, peça o payload de novo com `--reemitir`.
3. Espere com `jobs_wait` até o job terminar. Baixe o resultado com `curl -L` da `result_url` para um arquivo local fora de `clips/` (baixa validada com a conta real).
4. Descubra o **custo efetivo**: compare o `balance` antes e depois do job (ou use `transactions`) e **nunca repita a cotação** como se fosse o custo efetivo, senão um estouro nunca seria detectado. Se não conseguir determinar o custo, diga isso ao usuário e registre a cotação marcando como não verificado. Registre o clipe e o gasto efetivo:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/generate-clips.sh" "<gen-plan.json>" "<pasta de trabalho>" --generator mcp-agent --stage register --scene <id> --job-id <uuid do job> --custo <custo efetivo> --arquivo "<clipe baixado>" --budget "<budget.json>"
   ```
5. Se o registro terminar com **estouro** (código 3: o custo efetivo passou da cotação), o gasto já ficou registrado: **pare o lote** e converse com o usuário. Depois de um estouro os compromissos podem ultrapassar o teto, e então o sistema **recusa gerar qualquer cena nova** até uma decisão do usuário: aumentar o teto (`budget.py raise "<budget.json>" <novo teto>`, só com o "aprovo" dele) ou descartar cenas ainda não geradas (`budget.py drop`) e cotar de novo.
6. Variantes já pagas não são cobradas de novo: ao retomar, pule as cenas já registradas.

## 7. Montar o vídeo
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/assemble-clips.sh" "<gen-plan.json>" "<pasta de trabalho>/clips-manifest.json" "<pasta de trabalho>/video-gerado.mp4"
```
Une os clipes na ordem do plano em 1080x1920. Legendas, trilha e motion do modo gerado são etapas futuras (a edição das cenas geradas ainda não implementada).

## Regras
- **Nunca** envie `use_unlim` nem `use_free_gens`, nem use `preset_session_id`; não chame `get_katana_config` (ela cria sessão e pode gastar a geração grátis; não é consulta).
- Nunca invente custo, cotação ou `job_id`.
- Todo vídeo gerado por IA deve ser declarado como **conteúdo de IA** ao publicar (`isAiGenerated`/`isAigc` no agendador); avise isso na etapa de agendamento.
- Aprovação humana: do storyboard, do total de créditos e, depois, de cada post.
