---
name: schedule-post
description: Prepara a postagem de vídeos ou carrosséis prontos no Instagram e no TikTok (legenda, hashtags, dias e horários) e agenda pelo Metricool (MCP) ou entrega o pacote manual, sempre com aprovação explícita do usuário. Use depois que os vídeos/carrosséis finais estiverem prontos, quando o usuário quiser agendar ou postar.
---

# Agendamento de posts (com aprovação humana)

Converse em português do Brasil, uma pergunta por vez. **Nunca agende nem publique nada sem a aprovação explícita do usuário.**

## O que existe hoje (diga isso ao usuário)
- **Metricool (MCP)**: é o passo final automático. O script prepara o payload só a partir do que o usuário aprovou; **você (o agente) chama `createScheduledPost`** com ele. O payload foi conferido contra a definição da ferramenta, mas **ainda não foi validado em execução**: comece sempre em **modo teste** (ver passo 7). As mídias vão ao Metricool por links do Google Drive (sem API: pasta preparada + MCP do Drive só para buscar).
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
**Pré-requisitos** (confira, uma coisa por vez):
- **Metricool conectado ao Claude** e, **na própria marca do Metricool, o Instagram e/ou o TikTok conectados** (sem rede conectada, `getBrandSettings` dá erro e nada pode ser agendado; o erro traz o link para conectar). Rode `getBrandSettings` (só leitura): ele dá o `blogId` da marca, o **fuso** (use-o em `--timezone`) e as redes conectadas.
- **Google Drive conectado ao Claude** (MCP). O Metricool não aceita arquivo local, só link. Dois jeitos de ele ler o link do Drive:
  - **Pasta pública por link** (funciona em qualquer plano; é o que o usuário escolheu quando a integração do Drive do Metricool é paga): a pasta de mídias fica "**qualquer pessoa com o link: leitor**". **Isso expõe os arquivos a quem tiver o link: explique ao usuário e só siga com o "pode" explícito**; terminados os agendamentos, ofereça voltar a pasta para "restrito". Você **não consegue** fazer esse compartilhamento (`share_file` do MCP só compartilha com pessoas/grupos): peça ao usuário (Drive no navegador > botão direito na pasta > Compartilhar > Acesso geral > "Qualquer pessoa com o link" > Leitor).
  - **Drive vinculado na conta do Metricool** (integração paga do Metricool; arquivos privados). Use `--link view` no `drive_links.py`.

**Levar as mídias ao Drive, sem API nem credenciais** (depois de aprovar os posts):
1. Prepare a pasta (só posts aprovados, nomes únicos como `clo__p2__01__ab12cd34.png`):
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/stage_media.py" "<schedule-plan.json>" --approvals "<pasta de aprovações>" [--destino "<pasta>"]
   ```
   Padrão: `<pasta do plano>/para-drive`. Se o usuário tem o **Google Drive para computador**, use como `--destino` uma pasta dentro do Drive dele (ex.: `~/Google Drive/Meu Drive/Clo`): o upload é automático. Se não, peça que **arraste o conteúdo da pasta para o Drive no navegador** (uma ação só, para todos os posts).
2. Espere a sincronização/upload terminar e busque cada post com o MCP do Drive: `search_files` com `title contains 'clo__<post-id>__'` (use `excludeContentSnippets: true`). **Só leia**: nunca envie arquivos pelo MCP do Drive (`create_file` exige o conteúdo em base64 dentro da conversa: inviável para imagens e vídeos). No modo de pasta pública, **confira com `get_file_permissions`** (em um arquivo de cada post) que existe permissão do tipo `anyone` (leitor); se não houver, **pare** e peça ao usuário para compartilhar a pasta, em vez de agendar um link que o Metricool não consegue abrir.
3. Salve o resultado como veio em `found.json` (lista de `{id, name}`) e gere os links:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/drive_links.py" "<schedule-plan.json>" --found "<found.json>"
   ```
   Isso escreve `urls-<post-id>.json` (o `--urls` do agendamento; links diretos `uc?export=download`, ou `--link view` com o Drive vinculado no Metricool). Ele recusa se faltar arquivo (sincronização incompleta) ou houver cópia duplicada; nesse caso espere/limpe e busque de novo. O nome do arquivo leva o início do hash do conteúdo, então um arquivo trocado não é aceito.
- Alternativa avançada (opcional, exige uma credencial do Google Cloud): `drive_upload.py` envia por API (`docs/google-drive.md`). Não é o caminho padrão.
- O plano grátis do Metricool tem limite de posts agendados por mês (cerca de 20, a conferir): para 30 posts no mês, avise antes e planeje em lotes ou em plano pago.
- A conta que publica é a que a **marca** tem conectada em cada rede; `conta` no plano é só conferência. No TikTok, post só de fotos aceita imagens, mas a declaração de IA (`isAigc`) não vale para post só de fotos (a ferramenta a ignora): confira a regra da rede.

Para **cada post aprovado** (um por vez, nunca em lote sem confirmação):
1. **Simulação** (não grava nada, mostra o payload):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/schedule.sh" "<schedule-plan.json>" <post-id> --approvals "<pasta de aprovações>" --scheduler metricool --urls "<urls-<post-id>.json>" --blog-id <blogId> --timezone <fuso da marca> --modo teste
   ```
2. **Primeira vez: valide em modo teste** (`--modo teste`, o padrão): `autoPublish=false` (o Metricool **não publica sozinho**, só avisa o celular) e TikTok `SELF_ONLY` (só o dono vê). Confira no Metricool que o post apareceu certo antes de passar para `--modo real`. Só use `--modo real` depois dessa validação **e** de o usuário dizer "confirmo agendar de verdade".
3. Com a confirmação do usuário, rode o mesmo comando com `--confirm`. O script reserva o post e grava `.snapshots/<post>-*/metricool-payload.json`, **sem enviar nada**.
4. **Você chama `mcp__Metricool_Social_Media_Management__createScheduledPost`** com `blogId`, `date` e `info` exatamente como estão em `argumentos` nesse arquivo, sem alterar nada. Antes, compare cada campo com o esquema da ferramenta; se algum divergir, **pare e relate** (não adapte por conta própria). A data não pode estar no passado.
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
