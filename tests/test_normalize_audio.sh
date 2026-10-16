#!/usr/bin/env bash
# Testes de scripts/normalize-audio.sh

_lufs() { # arquivo → loudness integrado medido
  ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 \
    | python3 -c "
import sys, json, re
t = sys.stdin.read()
print(json.loads(re.search(r'\{[^{}]*\"input_i\"[^{}]*\}', t, re.S).group(0))['input_i'])"
}

test_loudness_near_target() {
  local f out before after; f="$(fixtures_dir)"; out="$(mktemp -d)"
  before="$(_lufs "$f/no_silence.mp4")"
  bash "$ROOT/scripts/normalize-audio.sh" "$f/no_silence.mp4" "$out/n.mp4" >/dev/null 2>&1 || _fail "normalize-audio falhou"
  after="$(_lufs "$out/n.mp4")"
  assert_near -14 "$after" 1.5 "loudness após normalizar (antes: $before)"
  assert_near 4 "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/n.mp4")" 0.15 "duração mantida"
  rm -rf "$out"
}

test_no_audio_errors_clearly() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  msg=$(bash "$ROOT/scripts/normalize-audio.sh" "$f/no_audio.mp4" "$out/n.mp4" 2>&1) && _fail "deveria falhar"
  assert_contains "$msg" "faixa de áudio" "mensagem"
  [ ! -e "$out/n.mp4" ] || _fail "não deveria criar saída"
  rm -rf "$out"
}
