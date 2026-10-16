#!/usr/bin/env bash
# Testes de scripts/reframe-9x16.sh

_dims() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height,sample_aspect_ratio -of csv=p=0:s=x "$1"; }

_reframe_case() { # entrada [modo]
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  if [ -n "${2:-}" ]; then
    bash "$ROOT/scripts/reframe-9x16.sh" "$f/$1" "$out/r.mp4" --mode "$2" >/dev/null 2>&1 || _fail "reframe falhou ($1 $2)"
  else
    bash "$ROOT/scripts/reframe-9x16.sh" "$f/$1" "$out/r.mp4" >/dev/null 2>&1 || _fail "reframe falhou ($1)"
  fi
  _dims "$out/r.mp4"
  rm -rf "$out"
}

test_horizontal_to_1080x1920() {
  assert_eq "1080x1920x1:1" "$(_reframe_case no_silence.mp4)" "blur"
  assert_eq "1080x1920x1:1" "$(_reframe_case no_silence.mp4 crop)" "crop"
}

test_vertical_to_1080x1920() {
  assert_eq "1080x1920x1:1" "$(_reframe_case vertical.mp4)" "vertical"
}

test_rotated_input_to_1080x1920() {
  assert_eq "1080x1920x1:1" "$(_reframe_case rotated.mp4)" "rotacionado"
}

test_keeps_audio_and_duration() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  bash "$ROOT/scripts/reframe-9x16.sh" "$f/no_silence.mp4" "$out/r.mp4" >/dev/null 2>&1 || _fail "reframe falhou"
  assert_near 4 "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/r.mp4")" 0.15 "duração"
  assert_eq audio "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$out/r.mp4")" "áudio mantido"
  rm -rf "$out"
}

test_rejects_unknown_mode_and_corrupt_input() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  assert_fails bash "$ROOT/scripts/reframe-9x16.sh" "$f/no_silence.mp4" "$out/r.mp4" --mode esticar
  assert_fails bash "$ROOT/scripts/reframe-9x16.sh" "$f/corrupt.mp4" "$out/r.mp4"
  [ ! -e "$out/r.mp4" ] || _fail "não deveria criar saída"
  rm -rf "$out"
}
