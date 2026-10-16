#!/usr/bin/env bash
# Testes de scripts/silence-detect.sh

_sd() { bash "$ROOT/scripts/silence-detect.sh" "$@"; }

test_detects_single_silence() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _sd "$f/tone_silence_tone.mp4" "$out/plan.json" >/dev/null 2>&1 || _fail "silence-detect falhou"
  assert_eq 1 "$(json_get "$out/plan.json" "len(d['cortes'])")" "um corte"
  assert_near 2.15 "$(json_get "$out/plan.json" "d['cortes'][0]['inicio_s']")" 0.1 "início"
  assert_near 3.35 "$(json_get "$out/plan.json" "d['cortes'][0]['fim_s']")" 0.1 "fim"
  assert_eq False "$(json_get "$out/plan.json" "d['approved']")" "não aprovado"
  python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/cut-plan.schema.json" "$out/plan.json" || _fail "plano inválido no schema"
  rm -rf "$out"
}

test_no_silence_gives_empty_cuts() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _sd "$f/no_silence.mp4" "$out/plan.json" >/dev/null 2>&1 || _fail "silence-detect falhou"
  assert_eq 0 "$(json_get "$out/plan.json" "len(d['cortes'])")" "sem cortes"
  rm -rf "$out"
}

test_no_audio_errors_clearly() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  msg=$(_sd "$f/no_audio.mp4" "$out/plan.json" 2>&1) && _fail "deveria falhar"
  assert_contains "$msg" "faixa de áudio" "mensagem"
  [ ! -e "$out/plan.json" ] || _fail "não deveria criar saída"
  rm -rf "$out"
}

test_all_silent_warns_and_writes_nothing() {
  local out msg; out="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=25:duration=3 -f lavfi -i anullsrc=r=44100:cl=mono \
    -t 3 -c:v libx264 -pix_fmt yuv420p -c:a aac "$out/mudo.mp4"
  msg=$(_sd "$out/mudo.mp4" "$out/plan.json" 2>&1) && _fail "deveria falhar"
  assert_contains "$msg" "silêncio" "mensagem cita silêncio"
  [ ! -e "$out/plan.json" ] || _fail "não deveria criar saída"
  rm -rf "$out"
}

test_spaced_accented_path_works() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _sd "$f/spaced name é.mp4" "$out/plano com espaço.json" >/dev/null 2>&1 || _fail "caminho com espaço/acento falhou"
  assert_file_exists "$out/plano com espaço.json"
  rm -rf "$out"
}

test_corrupt_file_errors_without_output() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  local msg
  msg=$(_sd "$f/corrupt.mp4" "$out/plan.json" 2>&1) && _fail "deveria falhar"
  assert_contains "$msg" "não foi possível ler" "mensagem clara"
  [ ! -e "$out/plan.json" ] || _fail "não deveria criar saída"
  rm -rf "$out"
}
