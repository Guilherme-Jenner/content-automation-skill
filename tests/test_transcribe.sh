#!/usr/bin/env bash
# Testes de scripts/transcribe.sh e scripts/whisper_to_transcript.py

test_fake_output_matches_schema() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  CLO_TRANSCRIBER=fake bash "$ROOT/scripts/transcribe.sh" "$f/tone_silence_tone.mp4" "$out/t.json" >/dev/null 2>&1 \
    || _fail "transcribe (fake) falhou"
  python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/transcript.schema.json" "$out/t.json" \
    || _fail "saída fora do schema"
  rm -rf "$out"
}

test_real_mode_without_whisper_gives_install_hint() {
  local empty out msg; empty="$(mktemp -d)"; out="$(mktemp -d)"
  msg=$(PATH="$empty" "$BASH" "$ROOT/scripts/transcribe.sh" "x.mp4" "$out/t.json" 2>&1) && _fail "deveria falhar"
  assert_contains "$msg" "brew install whisper-cpp" "dica de instalação"
  rm -rf "$empty" "$out"
}

test_real_mode_without_model_gives_download_hint() {
  local bin out msg f; f="$(fixtures_dir)"; bin="$(mktemp -d)"; out="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "$bin/whisper-cli"; chmod +x "$bin/whisper-cli"
  msg=$(PATH="$bin:$PATH" CLO_WHISPER_MODEL="$out/nao-existe.bin" bash "$ROOT/scripts/transcribe.sh" "$f/no_silence.mp4" "$out/t.json" 2>&1) \
    && _fail "deveria falhar"
  assert_contains "$msg" "modelo" "mensagem sobre o modelo"
  rm -rf "$bin" "$out"
}

test_whisper_json_conversion() {
  local out; out="$(mktemp -d)"
  python3 "$ROOT/scripts/whisper_to_transcript.py" "$ROOT/tests/data/whisper_cpp_sample.json" > "$out/t.json" \
    || _fail "conversão falhou"
  python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/transcript.schema.json" "$out/t.json" || _fail "fora do schema"
  assert_eq "pt" "$(json_get "$out/t.json" "d['idioma']")" "idioma"
  assert_eq "Olá, pessoal!" "$(json_get "$out/t.json" "d['segmentos'][0]['texto']")" "texto sem espaço inicial"
  assert_near 5.2 "$(json_get "$out/t.json" "d['segmentos'][1]['fim_s']")" 0.001 "fim em segundos"
  rm -rf "$out"
}
