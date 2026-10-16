---
name: edit-recorded
description: Edita um vídeo gravado (corte de silêncios e pausas, cortes criativos, áudio, 9:16 e legendas) de forma atrativa para a proposta do vídeo, com pesquisa e aprovação humana. Use quando o usuário informar o caminho de um vídeo gravado para editar.
---

# Edição do vídeo gravado

`${CLAUDE_PLUGIN_ROOT}` é a pasta onde o plugin está instalado; use-a em todos os comandos abaixo.

Converse em português do Brasil. Nada é cortado sem aprovação explícita do usuário.

## 0. Entrada
Peça o **caminho do arquivo** do vídeo no disco (não peça upload no chat) e confirme que ele existe. Confirme `ffmpeg` com `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"`.

## 1. Entenda a proposta e pesquise
1. Entenda a ideia e a proposta do vídeo (use o roteiro/shot list, se existir; senão pergunte: objetivo, público, plataforma).
2. Use a skill `research-trends` para gerar e validar o `research.json` (fontes reais). Sem `research.json` válido, não proponha edição criativa.
3. Escreva o **brief de edição** (`edit-brief.md` no diretório de trabalho): para a proposta do vídeo, defina ritmo e frequência de cortes, o que destacar (zoom, texto na tela), estilo de legenda, trilha e como prender a atenção nos primeiros segundos. Cada decisão cita o achado de `research.json` que a sustenta, ou diz que é hipótese.

## 2. Proponha (nada é alterado no vídeo original)
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/edit-recorded.sh" "<caminho do video>" "<diretorio de trabalho>" --stage propose
```
Isso grava `transcript.json` (Whisper local) e `cut-plan.json` com os cortes de silêncio (`approved: false`).
Leia a transcrição e **proponha cortes criativos** além dos silêncios, alinhados ao brief: takes repetidos, hesitações, trechos redundantes, abertura mais forte. Faça os ajustes **editando** `cut-plan.json` (lista `cortes` = trechos removidos, com `motivo`); não rode `propose` de novo, que apagaria o plano (só com `--force`).
Cortes que se tocam ou se sobrepõem aos de silêncio: junte-os em um só intervalo. Antes de mostrar o plano, valide:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_cutplan.py" "<diretorio de trabalho>/cut-plan.json"
```
Corrija até passar e só então mostre ao usuário um resumo claro: o que sai, por quê e o que muda na duração.

## 3. Aprovação (obrigatória)
Só marque `"approved": true` em `cut-plan.json` depois de o usuário confirmar de forma explícita ("aprovo"). Se ele pedir ajustes, edite o plano e mostre de novo. O script recusa planos não aprovados.

## 4. Aplique
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/edit-recorded.sh" "<caminho do video>" "<diretorio de trabalho>" --stage apply
```
Resultado: `final.mp4` (9:16, áudio normalizado, legenda queimada) e `final.srt`. Mostre o caminho ao usuário e peça a avaliação; ajustes voltam ao passo 2. Para refazer, use `--force`.

## Regras
- Nunca invente fonte ou dado. Se a pesquisa falhar, diga e trabalhe com hipóteses marcadas.
- O vídeo original nunca é modificado.
