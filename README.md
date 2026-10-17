# Clo Content Pipeline

Plugin do Claude Code que conduz a criação de vídeos curtos: roteiro → (gerado ou gravado) → edição → agendamento, sempre com aprovação humana antes de publicar.

Status: fases 1 e 1b (pesquisa, roteiro, edição com variantes e teto de gastos) e fase 2 (agendamento com aprovação; agendador real pendente). Veja `docs/arquitetura.md` e `docs/guia-mac-socio.md`.

## Testes
```bash
bash tests/run.sh
```
Nenhum teste chama serviço pago.
