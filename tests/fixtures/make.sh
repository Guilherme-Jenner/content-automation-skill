#!/usr/bin/env bash
# Gera os vídeos de teste em <dir> usando apenas ffmpeg (lavfi). Nada binário é versionado.
# Uso: make.sh <dir>
set -eu
dir="${1:?uso: make.sh <dir>}"
mkdir -p "$dir"

ff() { ffmpeg -v error -y "$@"; }
video() { # largura altura duração
  printf 'testsrc=size=%sx%s:rate=25:duration=%s' "$1" "$2" "$3"
}
tone() { printf 'sine=frequency=440:sample_rate=44100:duration=%s' "$1"; }
enc=(-c:v libx264 -pix_fmt yuv420p -c:a aac -shortest)

# tom 2 s + silêncio 1,5 s + tom 3 s
ff -f lavfi -i "$(video 1920 1080 6.5)" \
   -f lavfi -i "aevalsrc='if(between(t,2,3.5),0,0.5*sin(2*PI*440*t))':d=6.5:s=44100" \
   "${enc[@]}" "$dir/tone_silence_tone.mp4"

ff -f lavfi -i "$(video 1920 1080 4)" -f lavfi -i "$(tone 4)" "${enc[@]}" "$dir/no_silence.mp4"
ff -f lavfi -i "$(video 1920 1080 3)" -c:v libx264 -pix_fmt yuv420p -an "$dir/no_audio.mp4"
ff -f lavfi -i "$(video 1080 1920 3)" -f lavfi -i "$(tone 3)" "${enc[@]}" "$dir/vertical.mp4"
ff -display_rotation 90 -i "$dir/no_silence.mp4" -c copy "$dir/rotated.mp4"
cp "$dir/no_silence.mp4" "$dir/spaced name é.mp4"
head -c 4096 /dev/urandom > "$dir/corrupt.mp4"
