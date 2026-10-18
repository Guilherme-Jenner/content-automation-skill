# Remotion: legenda animada palavra a palavra

Camada de motion do pipeline. O visual é feito por um projeto Remotion (React) que recebe o `remotion-input.json` (contrato de `scripts/to_remotion_input.py`) e o vídeo já editado, e entrega um MP4 com legendas animadas. É o **último passo** da edição: rode depois que cortes, áudio, 9:16 e legendas do `.srt` já estiverem validados.

## Requisitos
- Node.js 18 ou mais novo (`brew install node` no Mac).
- Dependências, uma vez: `bash scripts/setup-remotion.sh` (faz `npm ci` pelo lockfile em `~/.cache/clo/remotion`, ou em `$CLO_REMOTION_HOME`; baixa pacotes e, no primeiro render, um Chrome headless). Ficam **fora do plugin** de propósito: o plugin instalado pelo marketplace mora num cache com o nome da versão, e dependências instaladas lá se perderiam a cada atualização. As fontes (`remotion/src`) são copiadas de novo a cada render.

## Uso
```bash
python3 scripts/to_remotion_input.py transcript.json video-editado.mp4 > remotion-input.json
bash scripts/render-remotion.sh remotion-input.json video-editado.mp4 video-final.mp4
```
- `--check-only` só valida o contrato e o vídeo, sem Node nem render (serve para testes).
- Estilos: `padrao`, `destaque` e `discreto` (campo `estilo` do JSON), espelhando os do `subtitles.sh`.
- Pré-visualização interativa (só no clone do repositório): `cd remotion && npm install && npm run studio`.

## Licença do Remotion
O Remotion tem licença própria (não é MIT): é gratuito para pessoas físicas e empresas pequenas, e empresas maiores precisam de licença comercial. Confira os termos atuais em https://www.remotion.pro/license antes de usar na empresa. O código deste repositório é MIT; o Remotion é uma dependência instalada por você e não vem junto.

## Validação
Validado em 2026-10-18 no Windows com Node 24: vídeo 1080x1920 de 5 s renderizado em cerca de 1,5 min nos três estilos, com áudio preservado e acentos corretos. A suíte automática testa o contrato, o agrupamento de palavras (com Node, se houver) e o fluxo do setup/render com `npm`/`npx` falsos, sem baixar nada. No Mac, repita `docs/testes-manuais.md` (seção Remotion) uma vez.
