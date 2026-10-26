# Google Drive: hospedagem das mídias para o Metricool

O Metricool só aceita mídia por **link** (o MCP dele não recebe arquivo). Em vez de o usuário subir tudo à mão, o `scripts/drive_upload.py` cria uma pasta no Google Drive e envia, **só dos posts já aprovados**, o vídeo ou as imagens do carrossel. O upload é feito por script (não pelo MCP do Drive): arquivos binários passando pelo contexto do Claude seriam inviáveis para dezenas de posts.

> Não foi validado contra o Google de verdade (os testes usam um servidor falso). Faça o primeiro envio com um post de teste.

## Configuração (uma vez, no terminal do usuário)
1. No [Google Cloud Console](https://console.cloud.google.com/): crie um projeto, ative a **Google Drive API** e, em *APIs e serviços > Credenciais*, crie um **ID do cliente OAuth** do tipo **App para computador**. Baixe o JSON (`client_secret.json`). Na tela de consentimento, adicione a sua conta como usuário de teste.
2. Rode (abre o navegador; o escopo pedido é só `drive.file`: a ferramenta enxerga apenas o que ela mesma cria, nunca o resto do seu Drive):
   ```bash
   python3 scripts/drive_upload.py auth --client-secret client_secret.json
   ```
   O token fica em `~/.config/clo-content-pipeline/drive-token.json` (permissão 0600). Não o envie a ninguém nem o coloque no repositório.
   Alternativa: exportar `GOOGLE_DRIVE_ACCESS_TOKEN` com um token de acesso já pronto.

## Uso
```bash
python3 scripts/drive_upload.py enviar plan.json --approvals ap/ --pasta "Clo Novembro" [--posts p1,p2] [--compartilhar-link] [--link view|download]
python3 scripts/drive_upload.py revogar plan.json
```
- Cria `Clo Novembro/<post-id>/` e envia as mídias dos posts com aprovação válida (os demais são pulados). Reenviar não duplica; mídia alterada depois da aprovação não é enviada.
- Grava `urls-<post-id>.json` ao lado do plano (entrada do `--urls` do `schedule.sh`) e `.drive-upload.json` (ids dos arquivos).
- **Privado por padrão.** Sem `--compartilhar-link`, o Metricool só lê os arquivos se o **Google Drive estiver vinculado na conta dele** (configuração dele). Com `--compartilhar-link`, qualquer pessoa com o link consegue abrir o arquivo: isso é publicar, só com o "pode" explícito do usuário. `revogar` remove o acesso por link (os arquivos continuam no Drive).
- Os formatos de link aceitos pelo Metricool não foram verificados em execução; teste `view` e, se ele recusar, `download`.
