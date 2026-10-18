# Changelog

Cada versão em `.claude-plugin/plugin.json` precisa de uma seção aqui. Quem instalou só recebe a atualização quando o `version` muda.

## 0.2.0
- Modo gerado: geração de clipes com cotação e confirmação do total, montagem, legendas por cena e trilha, e variantes (1 a 5 vídeos finais com os mesmos clipes).
- Teto de gastos opcional (`sem-teto`), escolhido ao iniciar o fluxo.
- Editor Katana real conduzido pelo agente (`edit-katana`), com aceitação explícita, limite opcional e registro do gasto.
- Projeto Remotion com legenda animada palavra a palavra (`render-remotion.sh`).
- Dezenas de correções de robustez (ids, caminhos, lotes parciais, mensagens em português).
- Marketplace do repositório (`clo-tools`) para instalar e atualizar sem reinstalar.

## 0.1.0
- Primeira versão: pesquisa, roteiro, edição do vídeo gravado com variantes e agendamento com aprovação (agendador real pendente).
