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
