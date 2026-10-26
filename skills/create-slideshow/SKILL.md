---
name: create-slideshow
description: Monta carrosséis nativos (Instagram) e slideshows em Modo Foto (TikTok): páginas PNG ordenadas, com vídeo opcional, a partir de fotos enviadas pelo usuário, com legenda em formato de roteiro (hook, problema, app, prova, CTA). Com as mesmas fotos faz várias versões, reordenando e variando hook e anúncio do app, com pesquisa e aprovação por variante. Use quando o usuário enviar fotos/imagens e pedir slideshow, carrossel ou vários vídeos a partir delas.
---

# Slideshow / carrossel a partir de fotos

O resultado é o **formato nativo das redes**: um conjunto de imagens numeradas na ordem de postagem. No Instagram é o **carrossel** (o usuário desliza); no TikTok é o **Modo Foto** (as fotos passam sozinhas, com música escolhida no app). Não é um vídeo: a rede cuida da passagem. O vídeo `.mp4` é só um extra opcional (por exemplo, para Reels). Os limites de fotos por post mudam com o tempo (hoje cerca de 20 no Instagram e 35 no TikTok; confirme no app), e o plano usa no máximo 10 slides por variante.

`${CLAUDE_PLUGIN_ROOT}` é a pasta onde o plugin está instalado; use-a em todos os comandos abaixo.

Converse em português do Brasil, uma pergunta por vez. Esta etapa **não gasta crédito** (tudo local, ffmpeg) e **não gera nem altera imagens**: só ordena as fotos do usuário e escreve o texto de cada slide. Nada é montado sem aprovação por variante.

## 0. Entrada
Peça a **pasta com as fotos** (ou os caminhos) no disco, não upload no chat. Copie/aponte as fotos para dentro do **diretório de trabalho** (o plano só aceita caminhos relativos a ele, sem `..`). Formatos: `.jpg`, `.jpeg`, `.png`, `.webp`; mínimo 3 fotos. Confirme o ffmpeg com `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh"`.

Abra e **olhe cada foto** (Read mostra a imagem) e escreva uma `descricao` curta do que ela mostra (tela do app, resultado, pessoa usando...). A ordem e o texto dependem disso; nunca invente o que a foto não mostra. Pergunte, se não estiver claro: o que o app faz, para quem, qual a ação final (CTA) e se há trilha (arquivo fornecido por ele; a licença é dele).

## 1. Pesquisa
Use a skill `research-trends` (gera `research.json` válido, com fontes) sobre hooks e formatos de carrossel/slideshow para o nicho. Sem `research.json` válido, não proponha. Cada variante cita em `achados` o achado que a sustenta, ou diz que é hipótese.

## 2. Estrutura do roteiro (cada variante)
Toda variante é uma sequência de 3 a 10 slides, uma foto por slide, sem repetir foto na mesma variante:

| papel | função | regra |
|---|---|---|
| `hook` | prende nos primeiros 2 s | **primeiro e único** |
| `problema` | a dor, o "antes" | opcional |
| `app` | apresenta o app / a solução | **ao menos um** |
| `prova` | resultado, benefício, números, depoimento | opcional |
| `cta` | chamada final | **último e único** |

`formato_hook` (como abre): `pergunta`, `resultado`, `polemica`, `erro_comum`, `historia`, `numero`.
`formato_anuncio` (como o app aparece): `demo`, `antes_depois`, `lista`, `depoimento`, `passo_a_passo`.

**A graça é reaproveitar as mesmas fotos:** com 10 fotos dá para fazer até 5 slideshows diferentes só reordenando e escolhendo quais fotos entram, trocando o hook e a forma de anunciar o app. Cada variante deve ter hook diferente (outro `formato_hook`) e uma ordem/seleção de fotos claramente diferente. Se faltar hook bom, repita o formato com `gancho_repetido: true` e `justificativa_gancho`, **e diga ao usuário**. Escolha a foto mais forte para o `hook` e a que mostra o app para o `app`.

Texto de cada slide: curto, no máximo **3 linhas na tela** (cerca de 51 caracteres no estilo `padrao`, 39 no `destaque`, 63 no `discreto`; o script recusa o que não couber). Duração padrão 2,5 s por slide (`duracao_s`, de 1,5 a 6 s; máximo de 60 s no vídeo). Vídeo gerado só com fotos reais do usuário; se a foto tiver conteúdo de IA, lembre de declarar ao publicar.

## 3. Plano
Escreva `slideshow-plan.json` no diretório de trabalho (formato em `${CLAUDE_PLUGIN_ROOT}/schemas/slideshow-plan.schema.json`; 1 a 5 variantes, `quantidade` igual ao número delas, `aprovada: false`):
```json
{"quantidade": 2, "estilo": "destaque",
 "fotos": [{"id": "f1", "arquivo": "fotos/tela-agenda.jpg", "descricao": "agenda semanal organizada no app"}, "..."],
 "variantes": [
   {"id": "A", "formato_hook": "pergunta", "formato_anuncio": "demo", "aprovada": false,
    "achados": ["pergunta no início retém mais (fonte em research.json)"],
    "slides": [
      {"foto": "f3", "papel": "hook", "texto": "Sua rotina vive bagunçada?"},
      {"foto": "f1", "papel": "app", "texto": "O Clo App organiza tudo"},
      {"foto": "f7", "papel": "cta", "texto": "Baixe o Clo App"}]},
   {"id": "B", "formato_hook": "resultado", "formato_anuncio": "antes_depois", "...": "..."}]}
```
Opcional por variante: `musica` (arquivo do usuário) e `volume_db` (-40 a 0). Valide antes de mostrar e corrija até passar:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_slideshow.py" "<diretorio de trabalho>/slideshow-plan.json"
```

## 4. Aprovação (obrigatória, por variante)
Mostre cada variante em linguagem simples: hook (formato), ordem das fotos com o papel e o texto de cada slide, como o app é anunciado e a duração total. Só marque `"aprovada": true` na variante que o usuário confirmar de forma explícita ("aprovo"); cada uma é aprovada separadamente. Se pedir ajustes, edite o plano, valide e mostre de novo.

## 5. Monte
Pergunte onde vai postar: **TikTok / Reels** usa `9:16` (1080x1920, o padrão); o **carrossel do feed do Instagram** costuma usar `4:5` (1080x1350).
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/make-slideshow.sh" "<diretorio de trabalho>/slideshow-plan.json" "<diretorio de saida>" [--aspecto 9:16|4:5] [--formato carrossel|video|ambos]
```
Para cada variante aprovada gera `carrossel-<id>/slide-01.png`, `slide-02.png`... (o texto do slide já está na imagem, na ordem de postagem). Com `--formato video` ou `ambos` gera também `slideshow-<id>.mp4` e `.srt` (cada foto na duração do slide, trilha opcional). Relata concluídas, puladas e falhas. Use `--only <id>` para uma só e `--force` para refazer. Mostre os caminhos e peça a avaliação; ajustes voltam ao passo 3.

## 6. Publicação
Siga a skill `schedule-post` (legenda do post, hashtags, horários, **aprovação por post**, e o agendamento pelo Metricool). No plano de agendamento, use `imagens` com as PNGs de `carrossel-<id>/` na ordem. Para postar à mão, o usuário sobe as PNGs na ordem `slide-01`, `slide-02`... no Instagram (carrossel) ou no TikTok (Modo Foto, onde escolhe a música no app). O pacote manual (`export_package.sh`) também aceita carrossel.

## Regras
- Nunca invente fonte ou dado; diga quando algo for hipótese.
- As fotos originais nunca são modificadas; o texto vai por cima, em cópias.
- Nada é montado, agendado ou publicado sem aprovação explícita do usuário.
- Limite atual: no vídeo opcional, transições são cortes secos; o texto fica na parte de baixo (estilo de legenda); a orientação EXIF de fotos de celular não foi verificada (se uma foto sair deitada, gire-a antes).
