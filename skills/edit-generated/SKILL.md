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
- até **126 caracteres** por legenda (3 linhas de 42), no máximo 40 legendas no vídeo;
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
- Combine o volume da trilha (`--volume-db`, de -40 a 0; padrão -18). Música mais longa que o vídeo é cortada com fade-out; mais curta é repetida.

## 3. Editar
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/edit-generated.sh" "<video-gerado.mp4>" "<gen-plan.json>" "<clips-manifest.json>" "<video-final.mp4>" --captions "<captions-plan.json>" --music "<musica>" --volume-db -18
```
Use só `--captions` ou só `--music` se for o caso (pelo menos uma é obrigatória). O script valida tudo antes de processar (as legendas contra a duração **real** dos clipes) e recusa a edição inteira se algo não conferir. A saída é 1080x1920, com áudio normalizado, e gera `<video-final>.srt` ao lado quando há legendas. Se a saída já existir, o script pede `--force`.

Depois, confira o resultado com o usuário (legendas legíveis, tempos, volume da trilha). Ajustes voltam ao passo 1 ou 2, e o usuário aprova de novo o que mudou.

## O que ainda não existe
- Variantes (vários vídeos finais a partir do mesmo bruto) no modo gerado ainda não implementadas: hoje existem só para o modo gravado.
- Movimento, efeitos e tipografia animada (Remotion) ainda não implementados; ficam para o fim do projeto.
- Ducking automático da trilha sobre uma fala: ainda não implementado (a trilha entra por baixo com mistura simples).

## Regras
- Nunca invente dado ou fonte; diga quando algo for hipótese.
- O vídeo gerado por IA deve ser declarado como **conteúdo de IA** ao publicar (veja a skill `schedule-post`).
- Não publique nem agende nada aqui: o próximo passo é a skill `schedule-post`, com aprovação por post.
