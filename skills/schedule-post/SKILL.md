---
name: schedule-post
description: Prepara a postagem de vídeos ou carrosséis prontos no Instagram e no TikTok (legenda, hashtags, dias e horários) e agenda pelo Metricool (MCP) ou entrega o pacote manual, sempre com aprovação explícita do usuário. Use depois que os vídeos/carrosséis finais estiverem prontos, quando o usuário quiser agendar ou postar.
---

# Agendamento de posts (com aprovação humana)

Converse em português do Brasil, uma pergunta por vez. **Nunca agende nem publique nada sem a aprovação explícita do usuário.**

## O que existe hoje (diga isso ao usuário)
- **Metricool (MCP)**: é o passo final automático. O script prepara o payload só a partir do que o usuário aprovou; **você (o agente) chama `createScheduledPost`** com ele. O contrato foi lido nas definições das ferramentas, mas **ainda não foi validado em execução**: comece sempre em **modo teste** (ver passo 7).
- **Pacote manual** (passo 8): continua valendo se o Metricool não estiver conectado, e para postar no app.
- O agendador `fake` só registra num arquivo local, para ensaiar. Ele não agenda nada de verdade.

## 1. Entradas
Os vídeos finais (`final-<id>.mp4`) **ou os carrosséis** (pasta `carrossel-<id>/` da skill `create-slideshow`) e o `research.json` da pesquisa. Sem `research.json` válido, use a skill `research-trends` antes.

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
Monte `schedule-plan.json` (formato em `schemas/schedule-plan.schema.json`: `id`, `legenda`, `hashtags`, `perfis`, `data_hora` e **uma** mídia: `video` (Reel/vídeo) **ou** `imagens` (carrossel, de 2 a 10 imagens **na ordem de postagem**, ex.: `["carrossel-A/slide-01.png", ...]`, dentro da pasta do plano)). Declare `"conteudo_ia": true` quando o vídeo/imagem for gerado ou muito alterado por IA (modo gerado): vai para a declaração de IA do Instagram/TikTok e entra na aprovação. Slideshow só com fotos reais do usuário: `false`. Valide:
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

## 7. Agendar pelo Metricool (passo final automático)
**Pré-requisitos** (peça ao usuário, uma coisa por vez): a conta do Metricool conectada ao Claude (conector/MCP) com Instagram e TikTok conectados na marca; o `blogId` da marca (use `getBrandSettings` para ver marca e fuso; sem rede conectada ele dá erro); e as **URLs públicas** das mídias.
- O Metricool **não aceita arquivo local**: só link público (ou Google Drive/Dropbox vinculado à conta dele). **Subir os arquivos é ação do usuário**: peça que suba cada arquivo (o vídeo, ou cada imagem do carrossel) e cole o link; **nunca hospede nem envie mídia a um serviço por conta própria**. Monte `media-urls.json` (`{"<caminho da mídia como está no plano>": "https://..."}`, um arquivo por post) e peça ao usuário para **abrir o link e conferir que é o arquivo certo** (o link não é verificado pelo script).
- O plano grátis do Metricool tem limite de posts agendados por mês (cerca de 20, a conferir): para 30 posts no mês, avise antes e planeje em lotes ou em plano pago.
- A conta que publica é a que a **marca** tem conectada em cada rede; `conta` no plano é só conferência. O Modo Foto do TikTok (carrossel) via Metricool **não foi verificado**.

Para **cada post aprovado** (um por vez, nunca em lote sem confirmação):
1. **Simulação** (não grava nada, mostra o payload):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/schedule.sh" "<schedule-plan.json>" <post-id> --approvals "<pasta de aprovações>" --scheduler metricool --urls "<media-urls.json>" --blog-id <blogId> --modo teste
   ```
2. **Primeira vez: valide em modo teste** (`--modo teste`, o padrão): `autoPublish=false` (o Metricool **não publica sozinho**, só avisa o celular) e TikTok `SELF_ONLY` (só o dono vê). Confira no Metricool que o post apareceu certo antes de passar para `--modo real`. Só use `--modo real` depois dessa validação **e** de o usuário dizer "confirmo agendar de verdade".
3. Com a confirmação do usuário, rode o mesmo comando com `--confirm`. O script reserva o post e grava `.snapshots/<post>-*/metricool-payload.json`, **sem enviar nada**.
4. **Você chama `createScheduledPost`** com os `argumentos` desse arquivo, sem alterar nada. Antes, compare cada campo com o esquema vivo da ferramenta carregada; se algum divergir, **pare e relate** (não adapte por conta própria). A data não pode estar no passado.
5. Registre o resultado:
   - criou: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/schedule_log.py" commit "<plano>" <post-id> "<pasta do plano>/.schedule-log.json" "<id ou plannerUrl devolvido>"`;
   - falhou e nada foi criado: `schedule_log.py release ... --conferido`; se houver dúvida se criou, **confira com `getScheduledPosts`** antes de liberar.
6. O mesmo post nunca é agendado duas vezes. Alterar um post já agendado: `updateScheduledPost` sobrescreve na hora (e troca o id), e o conteúdo precisa de nova aprovação; não há ferramenta de cancelar, então cancelamento é feito no app do Metricool, e só depois `schedule_log.py supersede`.

## 7b. Entrega manual (alternativa)
- **Pacote manual:**
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/export_package.sh" "<schedule-plan.json>" <post-id> "<pasta de saída>"
  ```
  Entrega o vídeo (ou `imagem-01`, `imagem-02`... do carrossel, para subir nessa ordem), `legenda.txt`, `horario.txt` e `COMO-AGENDAR.md`. O usuário agenda no app.
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
