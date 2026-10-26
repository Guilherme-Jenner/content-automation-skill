# Agendadores (MCP) para Instagram e TikTok: pesquisa e checklist de validação

Pesquisa feita em 2026-10-17, **somente leitura**: nada foi instalado, conectado, autenticado ou publicado. Tudo o que está abaixo é **descrição de terceiros** (páginas dos próprios fornecedores, diretórios de MCP, blogs) e fica marcado como **não verificado** até ser testado com uma conta de teste. Limites e regras das redes mudam; confira na documentação oficial antes de contar com qualquer número.

## Candidatos

| Candidato | O que a descrição diz | Vídeo: arquivo local ou URL? | Situação |
|---|---|---|---|
| **Metricool** (MCP oficial) | Ferramenta `post_schedule_post` agenda posts em várias redes, incluindo Instagram (Reels) e TikTok; cada rede vira um post agendado independente; há `update_schedule_post` e `get_best_time_to_post`; a rede precisa estar conectada à marca no Metricool; funciona em qualquer plano, inclusive Free | **Exige link direto do vídeo (URL pública)**; não aceita arquivo anexado no chat; link de página (YouTube, post do Instagram) falha; link do Google Drive só funciona se estiver como "qualquer pessoa com o link" | não verificado |
| **Planoly** (MCP remoto) | Servidor remoto com login OAuth; cria e agenda posts nos canais conectados, com opções do TikTok (som, privacidade) e reagendamento em horários sugeridos | não verificado | não verificado; não ficou claro se cobre Reels |
| **PostEverywhere** (MCP) | Servidor com muitas plataformas e ferramentas; a listagem diz agendar Reels do Instagram e vídeos do TikTok; roda hospedado ou local via `npx` | não verificado | não verificado |
| **Publora** (MCP) | Listagem cita agendamento de Reels e TikTok com controles de privacidade | não verificado | não verificado |
| CodivUpload, QPost | Citados na lista inicial do projeto; não foram pesquisados nesta rodada | não verificado | não pesquisado |
| Ferramentas de TikTok do **Higgsfield** | O MCP do Higgsfield expõe ferramentas com nomes `tiktok_accounts`, `tiktok_connect`, `tiktok_prepare_publish`, `tiktok_publish_status` | não verificado | **a descrição das ferramentas não foi lida**; não usar sem ler e sem permissão explícita (publicam em conta de terceiros) |

### Achado que muda o desenho
O Metricool, o candidato oficial e mais citado, pede o vídeo por **URL pública**. Isso significa que, com ele, o fluxo precisaria de um passo de hospedagem do vídeo (por exemplo, um link temporário). Hospedar o vídeo é publicá-lo em algum lugar, então **só com permissão explícita do usuário**, por vídeo. Até validar, o plano B (pacote manual, `export_package.sh`) continua sendo a entrega real.

### Agendamento nativo das redes (para o plano B)
Fontes de blogs divergem sobre a antecedência máxima do agendamento no Instagram/Meta Business Suite (aparecem 29, 75 e 90 dias, e "até um mês"). Não há confirmação do TikTok nesta pesquisa. **Conferir nas páginas de ajuda oficiais antes de afirmar qualquer limite.** O projeto usa o limite conservador de 30 dias.

## Checklist de validação com conta de teste
Para cada candidato, em uma **conta de teste** (nunca nos perfis reais do sócio no primeiro teste):

- [ ] Aceita vídeo por arquivo local ou exige URL pública? (se URL, onde hospedar e por quanto tempo)
- [ ] Agenda com data e hora exatas e respeita o fuso de Brasília (-03:00)?
- [ ] Publica no Instagram como Reel e no TikTok como vídeo, com a legenda e as hashtags exatamente como no plano?
- [ ] Funciona com os perfis do sócio (contas já conectadas) e quais permissões pede?
- [ ] Qual o limite de antecedência, de tamanho do vídeo e de duração?
- [ ] Dá para consultar, alterar e cancelar um post agendado (ID devolvido pela ferramenta)?
- [ ] Qual o custo/plano necessário, e o plano grátis cobre o teste?
- [ ] O que acontece se o mesmo post for enviado duas vezes (duplica?) e se o horário já passou?
- [ ] Como o agendador informa erro (vídeo recusado, conta desconectada) e o adaptador consegue relatar isso?
- [ ] O que sai dos nossos dados para o fornecedor (vídeo, legenda, contas) e isso é aceitável?

## Fontes consultadas (Acessado em 2026-10-17)
- Metricool, "Using Metricool within Claude Code": https://metricool.com/metricool-mcp-claude/
- Metricool, ajuda sobre agendar em horários diferentes por rede com o MCP: https://help.metricool.com/how-to-schedule-a-post-at-different-times-on-each-network-using-metricools-mcp-8tmhd
- Metricool MCP no Glama (README): https://glama.ai/mcp/servers/@metricool/mcp-metricool/blob/0d2346e07f6b7555e0a2ebc7698898583c37e27f/README.md
- Planoly MCP: https://mcpservers.org/servers/planoly/planoly-mcp
- PostEverywhere MCP (listagem): https://git.cynarski.dev/Awesome/awesome-mcp-servers/commit/de6da0da72849a43ef4af070266bbc1785ed2d01
- PostEverywhere, melhor agendador de TikTok (blog do fornecedor): https://posteverywhere.ai/blog/best-tiktok-scheduler
- Publora MCP no Glama: https://glama.ai/mcp/servers/bzpqoy3u30
- Agendar Reels com o Meta Business Suite (blog): https://recurpost.com/blog/schedule-instagram-reels-with-meta-business-suite
- Como agendar posts e Reels no Instagram em 2026 (blog): https://socialbu.com/blog/schedule-instagram-reels-and-posts

## Próximos passos (dependem do usuário)
1. Escolher o candidato (preferir a ferramenta que o sócio já paga) e criar uma conta de teste.
2. Rodar o checklist acima e registrar as respostas aqui.
3. Só então escrever o adaptador real atrás da porta `schedule.sh --scheduler <nome>`, com testes contra o agendador falso e uma validação manual na conta de teste.

## Atualização: Metricool, plano grátis e conexão (Acessado em 2026-10-17)
Informações lidas nas páginas do próprio fornecedor (descrição de terceiros, **não verificado** até o teste):
- Plano grátis: 1 marca, agendar até 20 posts por mês, 30 dias de analytics; redes exceto LinkedIn e Twitter/X, incluindo Instagram e TikTok. A página do MCP diz "no máximo 20 posts agendados" (a pricing diz "por mês"): conferir qual vale. Fonte: https://metricool.com/pricing/
- O MCP funciona em qualquer plano, inclusive o grátis; lista 27 ferramentas, entre elas `get_brands`, `post_schedule_post`, `update_schedule_post`, `get_scheduled_posts` e `get_best_time_to_post`. Autenticação: OAuth pelo navegador ou token (`METRICOOL_USER_TOKEN` e `METRICOOL_USER_ID`, nas configurações da conta; o local exato não foi dito). Fonte: https://metricool.com/metricool-mcp-claude/
- Não encontrado nas páginas lidas: o comando exato de instalação no Claude Code, os parâmetros de `post_schedule_post` e as regras de vídeo (a ajuda do fornecedor encontrada na busca fala em link direto/URL pública). O repositório citado pela página (github.com/metricool/mcp-metricool) respondeu 404 em 2026-10-17: conferir o endereço atual.
- Implicação do plano grátis (1 marca): a marca de teste usa os perfis de teste; trocar para os perfis reais do sócio exige reconectar ou subir de plano.

## Contratos reais das ferramentas do conector (Acessado em 2026-10-17, sem chamar nenhuma)
Fonte: as definições das ferramentas do conector "Metricool Social Media Management" (https://ai.metricool.com/mcp), carregadas no Claude depois que o usuário conectou a conta de teste. São a descrição do próprio fornecedor; **não verificado** em execução.

Ferramentas (9): `createScheduledPost`, `createScheduledPostForReview`, `sendScheduledPostForReview`, `updateScheduledPost`, `getScheduledPosts`, `getBrandSettings`, `getBestTimeToPostByNetwork`, `getAnalyticsAvailableMetrics`, `getAnalyticsDataByMetrics`.

- **Vídeo:** `media` aceita **URLs públicas**; links do Google Drive e do Dropbox são enviados ao Metricool automaticamente (o Drive precisa estar vinculado na conta do Metricool). Não existe ferramenta de upload de arquivo local: a **URL pública** (ou Drive/Dropbox) continua obrigatória.
- **Parâmetros de `createScheduledPost`:** `blogId` (id da marca), `date` (ISO 8601 com offset) e `info` (uma **string com JSON**, com `providers` como `[{"network":"instagram"}]`, `publicationDate` como `{dateTime, timezone IANA}` vindo de `getBrandSettings`, `text`, e `instagramData`/`tiktokData`). A data não pode estar no passado. A resposta traz um `plannerUrl`.
- **`autoPublish`** (padrão `true`): com `false`, o Metricool **não publica sozinho**; manda uma notificação ao app do celular e a pessoa conclui a publicação à mão. Isso encaixa na nossa regra de aprovação humana e vale testar. Também existe `draft`.
- **TikTok `privacyOption`:** aceita `SELF_ONLY` (só o dono vê). É o jeito mais seguro de testar uma publicação de verdade (confirmar se o Metricool respeita em conta pessoal).
- **Instagram:** `type` pode ser `POST`, `REEL`, `STORY` ou `TRIAL_REEL`; Reel exige vídeo; a trilha do Instagram (`audioConfiguration`) só vale para contas Business ligadas a uma Página do Facebook, o que indica requisito da conexão.
- **Conteúdo gerado por IA:** `instagramData.isAiGenerated` e `tiktokData.isAigc` declaram conteúdo gerado ou muito alterado por IA, como as redes exigem. Os vídeos do **modo gerado** (Higgsfield) devem declarar `true`. O `schedule-plan.json` precisa de um campo para isso (pendência de design).
- **Alterar e cancelar:** `updateScheduledPost` sobrescreve na hora, sem desfazer, e troca o `id` (o `uuid` fica). Entre as 9 ferramentas **não há ferramenta de cancelar** ou excluir; o cancelamento do post de teste provavelmente é feito no app do Metricool (não verificado).
- **Revisão/aprovação do Metricool** (`...ForReview`): exige um plano com gestão de equipe; provavelmente indisponível no grátis. Não é necessária, porque a aprovação é nossa.
- `getScheduledPosts` lista só posts agendados e ainda não publicados; exige `brandId`, `fromDate`, `toDate` e `timezone`.

### Consequência de arquitetura (executado pelo agente)
O MCP é uma ferramenta do **agente**, não algo que um script bash consiga chamar. Então o adaptador do Metricool não pode ser um `schedulers/metricool.sh`. O desenho é: (1) um script monta o payload exato a partir do **snapshot aprovado** (o mesmo que o `reserve` entrega ao agendador falso); (2) a chamada a `createScheduledPost` é **executado pelo agente**, com esse payload e nada mais; (3) o resultado (`plannerUrl`/id) volta ao log com `commit` (ou `release` se falhar). O `schedule.sh` ganha um modo em que apenas reserva e imprime o payload, sem chamar agendador. Isso fica registrado como a **Fase 2b**.

### Primeira chamada real (somente leitura): `getBrandSettings` (2026-10-17)
Chamada na conta de teste, sem nenhuma rede conectada. Resultado: **erro** dizendo que a marca ainda não tem nenhuma rede conectada e apontando para a tela de conexões do Metricool (o `blogId` da marca de teste aparece no link). Ou seja, enquanto nenhuma rede for conectada não dá para ver o fuso, as redes nem usar as outras ferramentas. Nenhuma outra ferramenta foi chamada; nada foi agendado nem publicado.

## Fase 2b implementada: adaptador do Metricool (2026-10-26)
Implementado como o desenho acima, **sem ter sido executado contra a conta real** (as ferramentas do Metricool não estavam conectadas na sessão de desenvolvimento; os testes cobrem só a preparação do payload e o log):
- `schedule.sh --scheduler metricool --urls <media-urls.json> --blog-id <id> [--modo teste|real] [--confirm]`: sem `--confirm` simula e mostra o payload; com `--confirm` reserva o post aprovado e grava `.snapshots/<post>-*/metricool-payload.json`, e para (reserva `em_andamento`).
- `metricool_payload.py` monta `createScheduledPost` (`blogId`, `date`, `autoPublish`, `info` como string JSON com `providers`, `publicationDate`, `text`, `media`, `instagramData`, `tiktokData`). Vídeo vira `REEL`, carrossel de imagens vira `POST`. Conteúdo de IA vai em `isAiGenerated`/`isAigc`.
- **Modo teste (padrão):** `autoPublish=false` e TikTok `SELF_ONLY`. **Modo real:** `autoPublish=true` e TikTok público; só depois da validação em teste e da confirmação do usuário.
- O agente chama a ferramenta com os `argumentos` do arquivo e registra com `schedule_log.py commit` (ou `release`).
- Incertezas a resolver na primeira execução real (conferir contra o esquema vivo): onde a lista de mídias entra em `info` (assumido `info.media`), o valor de `privacyOption` para TikTok público (assumido `PUBLIC_TO_EVERYONE`), suporte do TikTok em Modo Foto via Metricool, e o limite mensal de posts agendados do plano grátis.
- As URLs das mídias vêm de `stage_media.py` + `drive_links.py` (Google Drive, ver `docs/google-drive.md`) ou do usuário; o script não consegue verificar o conteúdo do link.
- **Conferido em 2026-10-26** contra a definição carregada de `createScheduledPost`: `info.media` aceita URLs públicas e links do Drive/Dropbox (o Drive precisa estar vinculado na conta do Metricool); `blogId` é texto; `privacyOption` aceita `PUBLIC_TO_EVERYONE` (padrão) e `SELF_ONLY`; TikTok aceita post só de imagens (`photoCoverIndex`, `title`); `isAigc` é ignorado em post só de fotos; `autoPublish` padrão é `true`. A chamada em si ainda não foi executada: a marca testada não tinha rede conectada (`getBrandSettings` devolveu esse erro).
