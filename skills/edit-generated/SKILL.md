---
name: edit-generated
description: Coloca legendas por cena e uma trilha sonora no vídeo montado do modo gerado, de forma atrativa e embasada na pesquisa, com aprovação do usuário. Use depois que os clipes forem gerados e montados com assemble-clips.sh.
---

# Edição do modo gerado: legendas e trilha

Converse em português do Brasil, uma pergunta por vez. Esta etapa **não gasta crédito**: tudo roda localmente (ffmpeg). O texto das legendas vem do **roteiro**, porque os clipes gerados não têm fala.

## Entradas
- O vídeo montado (`video-gerado.mp4`, de `assemble-clips.sh`), o `gen-plan.json` e o `clips-manifest.json` da etapa de geração.
- O `storyboard.json` aprovado e o `research.json` (se não houver `research.json` válido, use a skill `research-trends` antes).

## 1. Legendas por cena
Para cada cena, proponha **uma ou mais legendas curtas** que reforcem a mensagem do roteiro e prendam a atenção (cite o achado de `research.json` que justifica as escolhas, ou diga que é hipótese):
- no máximo **3 linhas na tela**: cabem em torno de 51 caracteres no estilo `padrao`, 39 no `destaque` e 63 no `discreto` (depende do tamanho das palavras; maiúsculas ocupam mais). O script recusa o que não couber; no máximo 40 legendas no vídeo;
- cada legenda dura pelo menos 0,8 s, dentro da cena, sem sobrepor outra da mesma cena;
- sem tempos, a legenda cobre a cena inteira (de 0,2 s até 0,2 s antes do fim); com `inicio_s` e `fim_s` você controla o ritmo (tempos relativos ao início da cena);
- estilo: `padrao`, `destaque` (maior e amarelo) ou `discreto`.

Mostre ao usuário, cena por cena, o texto e o tempo. **Só depois de uma aprovação explícita (por exemplo "aprovo")**, grave o `captions-plan.json` (formato em `schemas/captions-plan.schema.json`):
```json
{"estilo": "destaque", "cenas": [{"cena": "c1", "legendas": [{"texto": "Sua rotina vive bagunçada?"}]},
                                 {"cena": "c2", "legendas": [{"texto": "O Clo App organiza tudo", "inicio_s": 0.5, "fim_s": 3}]}]}
```

## 2. Trilha sonora (opcional)
Pergunte se o usuário quer trilha. Ela deve ser um **arquivo de áudio que o usuário já tem** (caminho local).
- A **licença da música é responsabilidade do usuário**: avise que a música precisa poder ser usada em publicações da empresa. Nunca invente trilha e **não baixe** música protegida; esta ferramenta também não gera música (isso gastaria crédito).
- As músicas em alta de cada rede costumam ser aplicadas no próprio app ao postar; isso não dá para automatizar aqui.
- Combine o volume da trilha (`--volume-db`, de -40 a 0; padrão -18), mas saiba que o volume **só tem efeito quando o vídeo já tem áudio** para misturar: nos clipes gerados sem áudio (o padrão) a trilha sai normalizada (~-14 LUFS) qualquer que seja o volume, e o script avisa. Música mais longa que o vídeo é cortada com fade-out; mais curta é repetida.

## 3. Editar
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/edit-generated.sh" "<video-gerado.mp4>" "<gen-plan.json>" "<clips-manifest.json>" "<video-final.mp4>" --captions "<captions-plan.json>" --music "<musica>" --volume-db -18
```
Use só `--captions` ou só `--music` se for o caso (pelo menos uma é obrigatória). O script valida tudo antes de processar (as legendas contra a duração **real** dos clipes) e recusa a edição inteira se algo não conferir. A saída é 1080x1920, com áudio normalizado, e gera `<video-final>.srt` ao lado quando há legendas. Se a saída já existir, o script pede `--force`.

Depois, confira o resultado com o usuário (legendas legíveis, tempos, volume da trilha). Ajustes voltam ao passo 1 ou 2, e o usuário aprova de novo o que mudou.

## 4. Variantes: de 1 a 5 vídeos finais com os mesmos clipes
Se o usuário quer mais de um vídeo final, cada variante recombina os **clipes já gerados**: outra seleção e ordem de cenas, outras legendas, outro estilo e, se quiser, outra trilha. Isso **não gasta crédito** e não mexe no teto. Clipes **novos** custam crédito: são da skill `generate-clips`, com teto e confirmação.
- Máximo de 5 variantes. Cada cena entra no máximo uma vez por variante; variantes idênticas são recusadas.
- O **gancho** de uma variante é a legenda que aparece primeiro (menor `inicio_s`) na primeira cena que tem legenda. Por padrão, os ganchos são diferentes entre as variantes; se não houver outro gancho bom, repita com `gancho_repetido: true` e `justificativa_gancho`, e varie o resto.
- Cada variante cita os achados de `research.json` que a justificam (`achados`), e só roda com `"aprovada": true` depois da aprovação explícita do usuário **por variante**.
- Grave o `gen-variants-plan.json` (formato em `schemas/gen-variants-plan.schema.json`; `legendas` tem o formato do `captions-plan.json`; `musica` é opcional e relativa à pasta do plano):
```json
{"quantidade": 2, "variantes": [
  {"id": "A", "cenas": ["c1", "c2", "c3"], "aprovada": true, "achados": ["pergunta no início retém mais"],
   "legendas": {"estilo": "padrao", "cenas": [{"cena": "c1", "legendas": [{"texto": "Sua rotina vive bagunçada?"}]}]}},
  {"id": "B", "cenas": ["c3", "c1"], "aprovada": true, "achados": ["resultado primeiro"], "musica": "trilha.mp3", "volume_db": -18,
   "legendas": {"estilo": "destaque", "cenas": [{"cena": "c3", "legendas": [{"texto": "Tudo em um lugar só"}]}]}}]}
```
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-gen-variants.sh" "<gen-plan.json>" "<clips-manifest.json>" "<pasta-de-saida>" --variants "<gen-variants-plan.json>"
```
O script valida **todas** as variantes aprovadas antes de produzir qualquer arquivo e entrega `final-<id>.mp4` e `final-<id>.srt` por variante. Se uma variante falhar na produção, as outras seguem e o script termina com erro listando as que falharam. Se a saída já existir, ele pede `--force`.

## O que ainda não existe
- Movimento, efeitos e tipografia animada (Remotion) ainda não implementados; ficam para o fim do projeto.
- Ducking automático da trilha sobre uma fala: ainda não implementado (a trilha entra por baixo com mistura simples).

## Regras
- Nunca invente dado ou fonte; diga quando algo for hipótese.
- O vídeo gerado por IA deve ser declarado como **conteúdo de IA** ao publicar (veja a skill `schedule-post`).
- Não publique nem agende nada aqui: o próximo passo é a skill `schedule-post`, com aprovação por post.
