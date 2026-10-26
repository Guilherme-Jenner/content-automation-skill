# Changelog

Cada versão em `.claude-plugin/plugin.json` precisa de uma seção aqui. Quem instalou só recebe a atualização quando o `version` muda.

## 0.3.0
- Slideshow/carrossel a partir de fotos do usuário (`create-slideshow`): roteiro por slide (hook, problema, app, prova, CTA), até 5 variantes reaproveitando as mesmas fotos com hooks e anúncios diferentes, aprovação por variante, PNGs do carrossel nativo (Instagram) / Modo Foto (TikTok) em 9:16 ou 4:5, com vídeo opcional (`make-slideshow.sh`), sem custo.

- Agendamento real pelo Metricool (MCP): `schedule.sh --scheduler metricool` reserva o post aprovado e prepara o payload de `createScheduledPost` (`metricool_payload.py`), o agente faz a chamada e registra com `commit`/`release`; modo teste (`autoPublish=false`, TikTok `SELF_ONLY`) e modo real; URLs públicas das mídias fornecidas pelo usuário. Não validado em execução.
- O plano de agendamento aceita carrossel (`imagens`, aprovação amarrada às imagens e à ordem) e a declaração de conteúdo de IA (`conteudo_ia`).

## 0.2.0
- Modo gerado: geração de clipes com cotação e confirmação do total, montagem, legendas por cena e trilha, e variantes (1 a 5 vídeos finais com os mesmos clipes).
- Teto de gastos opcional (`sem-teto`), escolhido ao iniciar o fluxo, com uma tabela de referência de custos (qualidade x duração -> créditos e valor aproximado) para ajudar a escolher.
- Editor Katana real conduzido pelo agente (`edit-katana`), com aceitação explícita, limite opcional e registro do gasto.
- Projeto Remotion com legenda animada palavra a palavra (`render-remotion.sh`).
- Dezenas de correções de robustez (ids, caminhos, lotes parciais, mensagens em português).
- Marketplace do repositório (`clo-tools`) para instalar e atualizar sem reinstalar.

## 0.1.0
- Primeira versão: pesquisa, roteiro, edição do vídeo gravado com variantes e agendamento com aprovação (agendador real pendente).
