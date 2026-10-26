# Google Drive: levando as mídias ao Metricool

O Metricool não recebe arquivo local; ele lê **links**, e os do Google Drive funcionam **se o Drive estiver vinculado na conta do Metricool** (os arquivos continuam privados). O MCP do Google Drive também não serve para enviar mídia (`create_file` exige o conteúdo em base64 dentro da conversa, inviável para imagens e vídeos). O caminho padrão, **sem API, sem Google Cloud e sem credenciais**, é:

1. `stage_media.py` copia as mídias **dos posts aprovados** para uma pasta, com nomes únicos (`clo__<post>__<NN>__<hash8>.<ext>`).
2. A pasta chega ao Drive por **uma** destas vias:
   - **Google Drive para computador** (recomendado): use como `--destino` uma pasta dentro do Drive (`~/Google Drive/Meu Drive/Clo`). Sincroniza sozinho.
   - **Arrastar no navegador**: arraste o conteúdo de `para-drive/` para o Drive (uma ação para todos os posts).
3. O Claude busca os arquivos com `search_files` do MCP do Drive (só leitura), e `drive_links.py` transforma o resultado em `urls-<post>.json`, que alimenta `schedule.sh --scheduler metricool --urls`.

## Configuração (uma vez por pessoa)
- No Metricool, vincule o Google Drive (configurações da conta > integrações) e conecte Instagram/TikTok na marca.
- No Claude, conecte os conectores **Google Drive** e **Metricool**.

## Comandos
```bash
python3 scripts/stage_media.py plan.json --approvals ap/ [--destino "<pasta>"] [--prefixo clo] [--posts p1,p2]
# (Claude: search_files com  title contains 'clo__<post>__'  → found.json)
python3 scripts/drive_links.py plan.json --found found.json [--link view|download]
```
- Só posts com aprovação válida são preparados; reexecutar não duplica; imagem alterada vira outro nome (outro hash).
- `drive_links.py` recusa se faltar arquivo (sincronização incompleta) ou houver duplicata no Drive.
- O formato do link (`view` por padrão) não foi verificado em execução; se o Metricool recusar, use `--link download`.

## Avançado (opcional): envio por API
`scripts/drive_upload.py` envia os arquivos direto pela API do Drive (cria a pasta, escopo `drive.file`, privado por padrão, `--compartilhar-link` só com o "pode" do usuário). Exige que a pessoa crie uma credencial OAuth no Google Cloud (`auth --client-secret client_secret.json`), por isso **não é o caminho padrão**. Só foi testado contra um servidor falso.
