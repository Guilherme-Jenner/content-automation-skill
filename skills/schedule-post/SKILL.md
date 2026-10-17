---
name: schedule-post
description: Prepara a postagem de vídeos prontos no Instagram e no TikTok (legenda, hashtags, dias e horários) e só segue com aprovação explícita do usuário. Use depois que os vídeos finais estiverem editados, quando o usuário quiser agendar ou postar.
---

# Agendamento de posts (com aprovação humana)

Converse em português do Brasil, uma pergunta por vez. **Nunca agende nem publique nada sem a aprovação explícita do usuário.**

## O que existe hoje (diga isso ao usuário)
- Agendadores reais (Metricool e outros, por MCP) **ainda não implementados**: dependem de testar com uma conta.
- O agendador `fake` só registra num arquivo local, para ensaiar o fluxo. **Ele não agenda nada de verdade.**
- Para postar de verdade hoje, gere o **pacote manual** (passo 7) e agende no próprio Instagram/TikTok, que têm agendamento nativo (conferir as regras no app).

## 1. Entradas
Os vídeos finais (`final-<id>.mp4`) e o `research.json` da pesquisa. Sem `research.json` válido, use a skill `research-trends` antes.

## 2. Perfis
Pergunte em quais redes (`instagram`, `tiktok`) e em quais contas cada vídeo vai. Um post pode ter vários perfis.

## 3. Legenda e hashtags
Proponha legenda e hashtags para cada vídeo, citando o achado de `research.json` que justifica as escolhas (ou dizendo que é hipótese). Os limites de legenda e de hashtags de cada rede mudam: **conferir** na rede; o validador usa um limite conservador.

## 4. Dias e horários
Pergunte (ou crie com o usuário) o arquivo `cadencia.json`: `{"dias":["seg","qua","sex"],"horarios":["12:00","19:00"],"minimo_entre_posts_h":6}`. Gere as datas:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/propose_slots.py" "<cadencia.json>" <quantidade de posts>
```
As datas ficam entre 15 minutos e 30 dias à frente, em horário de Brasília (`-03:00`). Se não houver horários suficientes, diga isso e ajuste a cadência com o usuário.

## 5. Plano e validação
Monte `schedule-plan.json` (formato em `schemas/schedule-plan.schema.json`: `id`, `video`, `legenda`, `hashtags`, `perfis`, `data_hora`) e valide:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_schedule.py" "<schedule-plan.json>"
```
Corrija até passar.

## 6. Aprovação (obrigatória, post a post)
Mostre cada post em linguagem simples: vídeo, legenda completa, hashtags, perfis, dia da semana, data e hora. Pergunte se pode aprovar. **Só depois de o usuário responder com uma aprovação explícita (por exemplo "aprovo")**, registre:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/approval.py" approve "<schedule-plan.json>" <post-id> "<pasta de aprovações>"
```
A aprovação fica amarrada ao hash do vídeo, da legenda, das hashtags, dos perfis e do horário. Se qualquer coisa mudar depois, a aprovação deixa de valer e é preciso pedir de novo. Aprovar um post não aprova os outros.

## 7. Entrega
- **Pacote manual (recomendado hoje):**
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/export_package.sh" "<schedule-plan.json>" <post-id> "<pasta de saída>"
  ```
  Entrega o vídeo, `legenda.txt`, `horario.txt` e `COMO-AGENDAR.md`. O usuário agenda no app.
- **Ensaio com o agendador `fake`:**
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/schedule.sh" "<schedule-plan.json>" <post-id> --approvals "<pasta de aprovações>" --scheduler fake
  ```
  Sem `--confirm` só simula (não grava nada). Com `--confirm` apenas registra no log local, que fica **sempre** em `.schedule-log.json` ao lado do plano (não existe opção para trocá-lo). Use `--confirm` somente depois de uma nova confirmação do usuário, e nunca apresente isso como um agendamento real. **Nunca use `--now`**: ele só existe nos testes; o prazo é sempre conferido contra a hora real.

## 8. Mudar ou refazer um post
- **Mudou a legenda, o horário, os perfis ou o vídeo depois de aprovar:** a aprovação deixa de valer; mostre de novo e peça um novo "aprovo".
- **O post já estava agendado e mudou:** o sistema recusa agendar o novo sem tratar o antigo. Peça ao usuário para **cancelar o post antigo no agendador/app**, confirmar que cancelou e só então registrar a substituição: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/schedule_log.py" supersede "<pasta do plano>/.schedule-log.json" <post-id>`. Depois aprove e agende o novo.
- **Reserva `em_andamento` que ficou presa** (um processo caiu): antes de liberar, **conferir no agendador** (app) se o post foi criado. Só se nada foi criado, libere com `schedule_log.py release <plano> <post-id> <log> --conferido`. Se o post foi criado, não libere: registre com `commit` o id que o agendador mostrar.
- Um post com horário vencido não impede os demais posts do plano; ele só não pode ser aprovado nem agendado.

## Limite desta aprovação
A aprovação é um controle de **procedimento**: protege contra mudanças acidentais e contra agendar algo diferente do que o usuário viu, mas não é uma assinatura criptográfica (quem editar os arquivos à mão consegue forjá-la). Por isso a regra de pedir o "aprovo" ao usuário vale sempre.

## Regras
- Nunca agende nem publique sem aprovação explícita do usuário, por post.
- Nunca invente dado ou fonte; diga quando algo for hipótese.
- Não mexa no vídeo, na legenda ou no horário depois da aprovação sem pedir uma nova aprovação.
