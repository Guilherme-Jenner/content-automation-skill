#!/usr/bin/env bash
# Testes de scripts/apply-cuts.sh

_ac() { bash "$ROOT/scripts/apply-cuts.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# _plan <arquivo> <approved true|false> <cortes json>
_plan() {
  printf '{"video":"x.mp4","duracao_s":6.5,"approved":%s,"cortes":%s}\n' "$2" "$3" > "$1"
}

test_refuses_unapproved_plan() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" false '[]'
  msg=$(_ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "aprovado" "mensagem cita aprovação"
  [ ! -e "$out/o.mp4" ] || _fail "não deveria gerar saída"
  rm -rf "$out"
}

test_applies_cut_duration() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" true '[{"inicio_s":2.0,"fim_s":3.2,"motivo":"silêncio"}]'
  _ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" >/dev/null 2>&1 || _fail "apply-cuts falhou"
  assert_near 5.3 "$(_dur "$out/o.mp4")" 0.15 "duração após corte"
  rm -rf "$out"
}

test_empty_cuts_keeps_duration() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" true '[]'
  _ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" >/dev/null 2>&1 || _fail "apply-cuts falhou"
  assert_near 6.5 "$(_dur "$out/o.mp4")" 0.15 "duração mantida"
  rm -rf "$out"
}

test_overlapping_cuts_rejected() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" true '[{"inicio_s":1,"fim_s":3,"motivo":"a"},{"inicio_s":2,"fim_s":4,"motivo":"b"}]'
  msg=$(_ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "sobrepõe" "mensagem"
  [ ! -e "$out/o.mp4" ] || _fail "não deveria gerar saída"
  rm -rf "$out"
}

test_cut_outside_duration_rejected() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" true '[{"inicio_s":6,"fim_s":9,"motivo":"a"}]'
  msg=$(_ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "fora da duração" "mensagem"
  _plan "$out/q.json" true '[{"inicio_s":3,"fim_s":2,"motivo":"a"}]'
  msg=$(_ac "$f/tone_silence_tone.mp4" "$out/q.json" "$out/o.mp4" 2>&1) && _fail "deveria recusar invertido"
  assert_contains "$msg" "invertido" "mensagem"
  rm -rf "$out"
}

test_refuses_overwrite_without_force() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" true '[]'
  echo existente > "$out/o.mp4"
  msg=$(_ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "--force" "mensagem"
  assert_eq existente "$(cat "$out/o.mp4")" "arquivo intacto"
  _ac "$f/tone_silence_tone.mp4" "$out/p.json" "$out/o.mp4" --force >/dev/null 2>&1 || _fail "--force deveria sobrescrever"
  rm -rf "$out"
}

test_no_partial_output_on_failure() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _plan "$out/p.json" true '[]'
  _ac "$f/corrupt.mp4" "$out/p.json" "$out/o.mp4" >/dev/null 2>&1 && _fail "deveria falhar"
  [ -z "$(find "$out" -mindepth 1 ! -name p.json)" ] || _fail "sobrou arquivo parcial: $(ls -A "$out")"
  rm -rf "$out"
}
