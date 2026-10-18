# Testes manuais (fora do CI)

Os testes automáticos nunca chamam serviços pagos nem o Whisper real. Estes roteiros cobrem o que só dá para validar com ferramentas reais.

## Transcrição com Whisper real (Mac ou Windows)
1. Instale: `brew install whisper-cpp ffmpeg` e baixe `ggml-small.bin` para `~/.cache/clo/` (ou aponte `CLO_WHISPER_MODEL`).
2. Grave 20–30 s falando em português, com pausas e uma frase repetida.
3. Rode `bash scripts/transcribe.sh meu-video.mp4 /tmp/transcript.json` e confira:
   - os textos batem com a fala (acentos corretos);
   - `inicio_s`/`fim_s` acompanham a fala (abra o vídeo e confira 3 trechos).
4. Anote o tempo de processamento e a qualidade para ajustar o modelo (`small` vs `medium`).

## Edição do gravado ponta a ponta
Veja `skills/edit-recorded/SKILL.md`. Use um vídeo real do celular (vertical e horizontal) e confira legenda, áudio e o corte dos silêncios.

## Remotion (legenda animada) no Mac
1. `brew install node` e `bash scripts/setup-remotion.sh` (aceite o download dos pacotes).
2. Gere um vídeo vertical curto de teste: `ffmpeg -f lavfi -i "gradients=s=1080x1920:d=5:r=30" -f lavfi -i "sine=frequency=330:duration=5" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac teste.mp4`.
3. Crie `t.json` (`{"idioma":"pt","segmentos":[{"inicio_s":0.3,"fim_s":2.4,"texto":"Sua rotina vive bagunçada hoje"}]}`), rode `python3 scripts/to_remotion_input.py t.json teste.mp4 > in.json` e `bash scripts/render-remotion.sh in.json teste.mp4 saida.mp4`.
4. Confira: 1080x1920, 5 s, com áudio, legenda palavra a palavra com a palavra ativa em amarelo e acentos corretos. Repita trocando `"estilo"` em `in.json` por `destaque` e `discreto`.
