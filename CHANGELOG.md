# Changelog

Cada versão em `.claude-plugin/plugin.json` precisa de uma seção aqui. Quem instalou só recebe a atualização quando o `version` muda.

## 0.3.0
- Slideshow: `hook_fixo` opcional no plano (mesmo formato e texto de hook em todas as variantes; o resto varia sem justificativa). O padrão continua sendo hook novo em cada variante, com roteiro de estrutura viral.
- TikTok em Modo Foto: música recomendada ligada (`autoAddMusic`); título vazio por padrão, só vai com `titulo_tiktok` no plano (até 90 unidades UTF-16, entra na aprovação). Validado em publicação real.
- Slideshow/carrossel a partir de fotos do usuário (`create-slideshow`): roteiro por slide (hook, problema, app, prova, CTA), até 5 variantes reaproveitando as mesmas fotos com hooks e anúncios diferentes, aprovação por variante, PNGs do carrossel nativo (Instagram) / Modo Foto (TikTok) em 9:16 ou 4:5, com vídeo opcional (`make-slideshow.sh`), sem custo.

- Agendamento real pelo Metricool (MCP): `schedule.sh --scheduler metricool` reserva o post aprovado e prepara o payload de `createScheduledPost` (`metricool_payload.py`), o agente faz a chamada e registra com `commit`/`release`; modo teste (`autoPublish=false`, TikTok `SELF_ONLY`) e modo real; URLs públicas das mídias fornecidas pelo usuário. Não validado em execução.
- O plano de agendamento aceita carrossel (`imagens`, aprovação amarrada às imagens e à ordem) e a declaração de conteúdo de IA (`conteudo_ia`).

- Mídias para o Metricool via Google Drive **sem API nem credenciais** (`stage_media.py` prepara a pasta dos posts aprovados; o usuário a leva ao Drive por sincronização ou arrastando; o Claude busca com o MCP do Drive e `drive_links.py` gera os links). O envio por API (`drive_upload.py`, exige credencial do Google Cloud) ficou como opção avançada. Pasta do Drive pública por link (padrão, funciona sem o plano pago do Metricool; confere a permissão com o MCP antes de agendar) ou Drive vinculado no Metricool (`--link view`). Validado com um agendamento real de teste (TikTok, carrossel de fotos, `SELF_ONLY`, `autoPublish=false`, pasta pública do Drive). Payload do Metricool conferido contra a definição real da ferramenta (`blogId` texto, `--timezone`, TikTok Modo Foto).

## 0.2.0
- Modo gerado: geração de clipes com cotação e confirmação do total, montagem, legendas por cena e trilha, e variantes (1 a 5 vídeos finais com os mesmos clipes).
- Teto de gastos opcional (`sem-teto`), escolhido ao iniciar o fluxo, com uma tabela de referência de custos (qualidade x duração -> créditos e valor aproximado) para ajudar a escolher.
- Editor Katana real conduzido pelo agente (`edit-katana`), com aceitação explícita, limite opcional e registro do gasto.
- Projeto Remotion com legenda animada palavra a palavra (`render-remotion.sh`).
- Dezenas de correções de robustez (ids, caminhos, lotes parciais, mensagens em português).
- Marketplace do repositório (`clo-tools`) para instalar e atualizar sem reinstalar.

## 0.1.0
- Primeira versão: pesquisa, roteiro, edição do vídeo gravado com variantes e agendamento com aprovação (agendador real pendente).
