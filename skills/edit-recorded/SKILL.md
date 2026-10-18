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

## 5. Várias versões do mesmo bruto (variantes)
Quando o usuário quiser mais de um vídeo final (de 1 a 5; o editor é `local`), em vez de um único `cut-plan.json` use um `variants-plan.json` no diretório de trabalho (formato em `${CLAUDE_PLUGIN_ROOT}/schemas/variants-plan.schema.json`). Rode antes o `propose` para obter `transcript.json`. Cada variante tem `tipo`:
- `trecho_diferente`: mostra outra parte do bruto;
- `mesmo_trecho_edicao_diferente`: mesma parte, com edição diferente (ritmo dos cortes e estilo de legenda: `padrao`, `destaque` ou `discreto`).

O `gancho` de cada variante é a ideia de abertura que a variante defende: no editor local ele é definido pelos **trechos que abrem o vídeo** e pelo texto da legenda do post, mas **não é renderizado** como texto ou efeito pelo editor. Duas variantes com os mesmos trechos, ritmo e estilo saem idênticas (o validador avisa).

Regras da proposta:
- Cada variante tem um **gancho distinto**, ligado a um achado de `research.json` (campo `achados`). Se, na quantidade pedida, não houver outro gancho bom o bastante, repita um gancho: marque `gancho_repetido: true`, escreva `justificativa_gancho`, **diga isso ao usuário** e varie o restante (ritmo, trechos, legenda).
- Não proponha variantes quase idênticas; prefira trechos diferentes ou ritmos claramente diferentes.
- Valide antes de mostrar: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_variants.py" "<diretorio de trabalho>/variants-plan.json"`.
- Mostre cada variante em linguagem simples (trechos, gancho, ritmo, legenda, duração final). **Aprovação é por variante**: só marque `aprovada: true` na que o usuário confirmar; cada variante é aprovada separadamente.

Aplicação:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/edit-recorded.sh" "<caminho do video>" "<diretorio de trabalho>" --stage apply --variants "<diretorio de trabalho>/variants-plan.json"
```
Gera `final-<id>.mp4` e `.srt` para cada variante aprovada e relata concluídas, puladas e falhas. O editor `katana` ainda não implementado: se o plano pedir `katana`, ofereça `local`.

## Regras
- Nunca invente fonte ou dado. Se a pesquisa falhar, diga e trabalhe com hipóteses marcadas.
- O vídeo original nunca é modificado.
