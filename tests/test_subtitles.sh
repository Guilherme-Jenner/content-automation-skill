#!/usr/bin/env bash
# Testes de scripts/transcript_to_srt.py e scripts/subtitles.sh

_srt() { python3 "$ROOT/scripts/transcript_to_srt.py" "$@"; }

test_srt_format_and_order() {
  local d out; d="$(mktemp -d)"
  printf '%s' '{"idioma":"pt","segmentos":[{"inicio_s":3.5,"fim_s":5.25,"texto":"Segundo"},{"inicio_s":0,"fim_s":1.8,"texto":"Primeiro"}]}' > "$d/t.json"
  out=$(_srt "$d/t.json")
  assert_contains "$out" "1
00:00:00,000 --> 00:00:01,800
Primeiro" "primeiro bloco"
  assert_contains "$out" "2
00:00:03,500 --> 00:00:05,250
Segundo" "segundo bloco"
  rm -rf "$d"
}

test_srt_wraps_long_lines() {
  local d out longest; d="$(mktemp -d)"
  printf '%s' '{"idioma":"pt","segmentos":[{"inicio_s":0,"fim_s":4,"texto":"Esta é uma frase bem longa que precisa ser quebrada em várias linhas para caber na tela do celular"}]}' > "$d/t.json"
  out=$(_srt "$d/t.json")
  longest=$(printf '%s\n' "$out" | python3 -c "
import sys
print(max(len(l.rstrip('\n')) for l in sys.stdin if '-->' not in l and not l.strip().isdigit()))")
  [ "$longest" -le 42 ] || _fail "linha com $longest caracteres (máx 42)"
  rm -rf "$d"
}

test_srt_keeps_accents_and_quotes() {
  local d out; d="$(mktemp -d)"
  printf '%s' '{"idioma":"pt","segmentos":[{"inicio_s":0,"fim_s":2,"texto":"Ação \"rápida\" d'"'"'água"}]}' > "$d/t.json"
  out=$(_srt "$d/t.json")
  assert_contains "$out" "Ação \"rápida\" d'água" "texto preservado"
  rm -rf "$d"
}

test_empty_segments_dropped_and_times_clamped() {
  local d out; d="$(mktemp -d)"
  printf '%s' '{"idioma":"pt","segmentos":[{"inicio_s":0,"fim_s":1,"texto":"  "},{"inicio_s":1,"fim_s":9,"texto":"Vale"},{"inicio_s":7,"fim_s":8,"texto":"Fora"}]}' > "$d/t.json"
  out=$(_srt "$d/t.json" 5)
  assert_contains "$out" "00:00:01,000 --> 00:00:05,000" "fim limitado à duração"
  case "$out" in *Fora*) _fail "segmento fora da duração deveria sair" ;; esac
  assert_eq 1 "$(printf '%s\n' "$out" | grep -c -e '-->')" "um único bloco"
  rm -rf "$d"
}

test_burn_in_with_special_path() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)/dir com espaço & é"; mkdir -p "$d"
  cp "$f/no_silence.mp4" "$d/vídeo 1.mp4"
  CLO_TRANSCRIBER=fake bash "$ROOT/scripts/transcribe.sh" "$d/vídeo 1.mp4" "$d/t.json" >/dev/null 2>&1
  bash "$ROOT/scripts/subtitles.sh" "$d/vídeo 1.mp4" "$d/t.json" "$d/saída.mp4" >/dev/null 2>&1 || _fail "subtitles.sh falhou"
  assert_file_exists "$d/saída.srt"
  assert_near 4 "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$d/saída.mp4")" 0.15 "duração mantida"
  rm -rf "$d"
}
