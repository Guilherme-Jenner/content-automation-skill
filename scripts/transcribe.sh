#!/usr/bin/env bash
# Transcreve o áudio de um vídeo para o formato transcript (JSON).
# Uso: transcribe.sh <video> <saida.json> [--lang pt] [--force]
# CLO_TRANSCRIBER=fake usa um transcript fixo (testes, sem Whisper).
# Modo real: whisper.cpp (`whisper-cli`) com o modelo em $CLO_WHISPER_MODEL
# (padrão: ~/.cache/clo/ggml-small.bin).
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; args=()
for a in "$@"; do if [ "$a" = "--force" ]; then force=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || die "uso: transcribe.sh <video> <saida.json> [--lang pt] [--force]"
video="$(abspath "$1")"; out="$(abspath "$2")"; lang=pt
if [ "${3:-}" = "--lang" ]; then [ $# -ge 4 ] || die "--lang exige o idioma (ex.: pt)"; lang="$4"; fi
refuse_existing "$out" "$force"

if [ "${CLO_TRANSCRIBER:-}" = "fake" ]; then
  cp "${CLO_FAKE_TRANSCRIPT:-$here/../tests/data/transcript_fake.json}" "$out"
  exit 0
fi

need_cmd whisper-cli "brew install whisper-cpp"
model="${CLO_WHISPER_MODEL:-$HOME/.cache/clo/ggml-small.bin}"
[ -f "$model" ] || die "modelo do Whisper não encontrado em $model. Baixe o ggml-small.bin (https://huggingface.co/ggerganov/whisper.cpp) e coloque nesse caminho, ou defina CLO_WHISPER_MODEL"
need_cmd ffmpeg "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "arquivo não encontrado: $video"

work="$(tmpdir)"
trap 'rm -rf "$work"' EXIT
ffmpeg -v error -y -i "$video" -vn -ac 1 -ar 16000 "$work/audio.wav" || die "não foi possível extrair o áudio de $video"
whisper-cli -m "$model" -l "$lang" -oj -of "$work/saida" -f "$work/audio.wav" >/dev/null 2>&1 \
  || die "o Whisper falhou ao transcrever $video"
python3 "$here/whisper_to_transcript.py" "$work/saida.json" > "$work/transcript.json"
mv "$work/transcript.json" "$out"
