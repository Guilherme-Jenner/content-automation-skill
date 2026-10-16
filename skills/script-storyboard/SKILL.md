---
name: script-storyboard
description: Cria hook, roteiro e storyboard (modo gerado) ou shot list (modo gravado) para vídeos curtos do Clo App. Use quando o usuário pedir roteiro, hook, storyboard ou lista de takes para gravar.
---

# Roteiro, hook e storyboard

Você conduz a criação do roteiro de um vídeo curto (vertical, 9:16) do Clo App. Converse em português do Brasil.

## 1. Perguntas iniciais
Pergunte, uma de cada vez, só o que ainda não foi dito:
1. Tema ou objetivo do vídeo e público.
2. Duração-alvo em segundos (padrão: 30).
3. **Modo**: `gerado` (clipes criados por IA) ou `gravado` (o usuário grava). Se o pedido já indicar o modo, deduza e confirme em uma frase.

## 2. Pesquisa antes do hook
Antes de propor qualquer hook ou roteiro, use a skill `research-trends` para gerar e validar o `research.json` dessa proposta (fontes reais, `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check_research.py" research.json`). Sem `research.json` válido, não proponha roteiro.

## 3. Hook e roteiro
- O objetivo é **atrair e prender a atenção**: cada escolha (hook, estrutura, duração, chamada para ação) deve citar o achado da pesquisa que a justifica; o que for palpite, diga que é hipótese.
- Escreva 3 opções de hook (primeiros 3 segundos) e peça para o usuário escolher.
- Escreva o roteiro com início (hook), problema, solução (Clo App) e chamada para ação.

## 4. Saída estruturada
Salve o resultado em JSON e valide **antes de mostrar como pronto**:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_json.py" "${CLAUDE_PLUGIN_ROOT}/schemas/storyboard.schema.json" arquivo.json   # modo gerado
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_json.py" "${CLAUDE_PLUGIN_ROOT}/schemas/shot-list.schema.json" arquivo.json    # modo gravado
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check_durations.py" arquivo.json                                # soma bate com o alvo
```

### Modo gerado
`storyboard.json`: cada cena tem `id`, `descricao`, `duracao_s` e `prompt` (descrição visual para o gerador de vídeo, em formato vertical). Cenas de 3 a 8 segundos.

### Modo gravado
`shot-list.json`: cada take tem `id`, `enquadramento`, `fala` (texto exato a falar) e `duracao_s`. Dê dicas curtas de gravação (luz, áudio, fundo).
Depois que o usuário gravar, peça o **caminho do arquivo** do vídeo no disco (não peça upload no chat) e siga para a skill `edit-recorded`.

## Regras
- Se a validação ou a soma das durações falhar, corrija e valide de novo.
- Não avance para geração ou edição sem o usuário aprovar o roteiro.
