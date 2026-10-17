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
