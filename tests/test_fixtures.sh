#!/usr/bin/env bash
# Testes de tests/fixtures/make.sh

_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

test_fixture_durations() {
  local d; d="$(mktemp -d)"
  bash "$ROOT/tests/fixtures/make.sh" "$d" >/dev/null 2>&1 || _fail "make.sh falhou"
  assert_near 6.5 "$(_dur "$d/tone_silence_tone.mp4")" 0.1 "tone_silence_tone"
  assert_near 4 "$(_dur "$d/no_silence.mp4")" 0.1 "no_silence"
  assert_near 3 "$(_dur "$d/vertical.mp4")" 0.1 "vertical"
  local audio
  audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$d/no_audio.mp4")
  assert_eq "" "$audio" "no_audio.mp4 não deve ter áudio"
  assert_file_exists "$d/spaced name é.mp4"
  assert_file_exists "$d/rotated.mp4"
  assert_fails ffprobe -v error "$d/corrupt.mp4"
  rm -rf "$d"
}
