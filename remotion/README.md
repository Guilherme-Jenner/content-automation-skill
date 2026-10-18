# Remotion: legenda animada palavra a palavra

Camada de motion do pipeline. O visual é feito por um projeto Remotion (React) que recebe o `remotion-input.json` (contrato de `scripts/to_remotion_input.py`) e o vídeo já editado, e entrega um MP4 com legendas animadas. É o **último passo** da edição: rode depois que cortes, áudio, 9:16 e legendas do `.srt` já estiverem validados.

## Requisitos
- Node.js 18 ou mais novo (`brew install node` no Mac).
- Dependências do projeto, uma vez: `cd remotion && npm install` (baixa o Remotion e, no primeiro render, um Chrome headless).

## Uso
```bash
python3 scripts/to_remotion_input.py transcript.json video-editado.mp4 > remotion-input.json
bash scripts/render-remotion.sh remotion-input.json video-editado.mp4 video-final.mp4
```
- `--check-only` só valida o contrato e o vídeo, sem Node nem render (serve para testes).
- Estilos: `padrao`, `destaque` e `discreto` (campo `estilo` do JSON), espelhando os do `subtitles.sh`.
- Pré-visualização interativa: `cd remotion && npm run studio`.

## Licença do Remotion
O Remotion tem licença própria (não é MIT): é gratuito para pessoas físicas e empresas pequenas, e empresas maiores precisam de licença comercial. Confira os termos atuais em https://www.remotion.pro/license antes de usar na empresa. O código deste repositório é MIT; o Remotion é uma dependência instalada por você e não vem junto.

## Validação
O render real depende do Node, das dependências e do Chrome headless e é validado à mão (`docs/testes-manuais.md`); a suíte automática só testa o contrato e o script de entrada.
