# Guia de instalação no Mac

1. Instale o Homebrew (https://brew.sh) se ainda não tiver.
2. Dependências:
   ```bash
   brew install ffmpeg whisper-cpp shellcheck
   ```
3. Modelo do Whisper (uma vez):
   ```bash
   mkdir -p ~/.cache/clo
   curl -L -o ~/.cache/clo/ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
   ```
4. Confira: `bash scripts/check-deps.sh`
5. Instalação do plugin pelo marketplace do Claude Code: será documentada na fase de empacotamento.
