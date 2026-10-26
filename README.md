# Clo Content Pipeline

Plugin do Claude Code que conduz a criação de vídeos curtos (9:16) de ponta a ponta, sempre com aprovação humana antes de qualquer custo ou publicação:

**pesquisa → roteiro → modo (gerado ou gravado) → edição → agendamento**

Feito para uso interno da CLO (app Clo) e aberto para quem quiser adaptar. A conversa com o usuário e os textos de saída são em português do Brasil.

## O que já existe

| Etapa | Skill | O que faz |
|---|---|---|
| Orquestração | `content-pipeline` | Pergunta o modo, o editor e quantos vídeos (1 a 5) e chama as demais |
| Pesquisa | `research-trends` | Pesquisa com fontes reais antes de propor roteiro e edição |
| Roteiro | `script-storyboard` | Gancho, roteiro e storyboard, com aprovação |
| Modo gerado | `generate-clips` | Gera clipes no Higgsfield com **teto de créditos**: cotação, confirmação do total e gasto dentro do teto |
| Edição (gerado) | `edit-generated` | Legendas por cena e trilha sobre o vídeo montado; **variantes** (1 a 5 finais com os mesmos clipes); sem gastar crédito |
| Edição (gravado) | `edit-recorded` | Cortes de silêncio, legendas (Whisper), áudio, 9:16; variantes; aprovação dos cortes |
| Edição com Katana | `edit-katana` | Edição autônoma no Higgsfield (gasta sozinha, dentro do limite opcional que você der), com registro do resultado e do gasto |
| Slideshow / carrossel | `create-slideshow` | Fotos do usuário viram até 5 slideshows (vídeo 9:16 + PNGs do carrossel) reordenando as mesmas fotos, com legenda em formato de roteiro (hook, app, prova, CTA) e aprovação por variante; sem custo |
| Agendamento | `schedule-post` | Legenda, hashtags, horários, **aprovação por post** amarrada ao conteúdo; pacote manual de entrega |

Ainda não existem: agendador real por MCP (hoje a entrega é o pacote manual), motion/efeitos com Remotion (último passo do plano), e o empacotamento final para instalação pelo marketplace.

## Garantias de segurança

- Nada é publicado nem agendado sem aprovação explícita, por post.
- Tudo que consome crédito é registrado em `scripts/budget.py`: cotar → confirmar o total → gerar → registrar o gasto. O **teto é opcional** (você escolhe ao iniciar; pode ser `sem-teto`); com teto, estouro é registrado e interrompe o lote.
- Vídeo gerado por IA deve ser declarado como conteúdo de IA ao publicar.
- A trilha sonora é sempre um arquivo fornecido pelo usuário; a licença da música é responsabilidade dele. Nada é baixado nem gerado.
- Nenhum teste chama serviço pago: geradores, editor Katana, transcritor e agendador têm versões falsas.

## Requisitos

- Claude Code
- `ffmpeg` (inclui `ffprobe`), `python3` (só biblioteca padrão), bash
- `whisper-cpp` e um modelo `ggml` para transcrever o vídeo gravado
- Para as etapas que usam serviços externos (Higgsfield, Metricool), cada pessoa precisa da **própria conta** e deve seguir os termos de cada serviço

No Mac: `brew install ffmpeg whisper-cpp` (guia completo em `docs/guia-mac-socio.md`). Confira com:

```bash
bash scripts/check-deps.sh
```

No Windows, use o Git Bash (os scripts são bash/POSIX).

## Testes

```bash
bash tests/run.sh            # todos
bash tests/run.sh captions   # só os arquivos cujo nome contém "captions"
```

## Documentação

- `docs/arquitetura.md`: como as peças se ligam
- `docs/guia-mac-socio.md`: instalação no Mac
- `docs/agendadores.md`: agendadores avaliados e contratos reais do Metricool
- `docs/validacao-contas-teste.md` e `docs/testes-manuais.md`: roteiros de validação com contas reais, sem gastar crédito nem publicar
- `docs/superpowers/`: especificação e planos de cada fase

## Licença

MIT. Veja o arquivo `LICENSE`.
