#!/usr/bin/env bash
# Testes de scripts/to_remotion_input.py (contrato com o Remotion; visual fica para a fase 5)

_conv() { python3 "$ROOT/scripts/to_remotion_input.py" "$ROOT/tests/data/transcript_fake.json" "$1"; }

test_output_validates_against_schema() {
  local d; d="$(mktemp -d)"
  _conv final.mp4 > "$d/in.json" || _fail "conversão falhou"
  python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/remotion-input.schema.json" "$d/in.json" || _fail "fora do schema"
  assert_eq "final.mp4" "$(json_get "$d/in.json" "d['video']")" "video"
  assert_eq "1080" "$(json_get "$d/in.json" "d['largura']")" "largura"
  rm -rf "$d"
}

test_words_cover_segment_time_without_overlap() {
  local d; d="$(mktemp -d)"
  _conv final.mp4 > "$d/in.json"
  # transcript_fake: "Olá, pessoal!" 0-1.8 e "Hoje vou mostrar o Clo App." 3.5-5.2 (6 palavras)
  assert_eq 8 "$(json_get "$d/in.json" "len(d['palavras'])")" "2 + 6 palavras"
  assert_near 0 "$(json_get "$d/in.json" "d['palavras'][0]['inicio_s']")" 0.001 "primeira palavra começa no segmento"
  assert_near 1.8 "$(json_get "$d/in.json" "d['palavras'][1]['fim_s']")" 0.001 "última do segmento 1 termina no fim"
  assert_near 5.2 "$(json_get "$d/in.json" "d['palavras'][-1]['fim_s']")" 0.001 "última palavra termina no fim"
  assert_eq True "$(json_get "$d/in.json" "all(a['fim_s'] <= b['inicio_s'] + 1e-9 for a, b in zip(d['palavras'], d['palavras'][1:]))")" "sem sobreposição"
  assert_eq True "$(json_get "$d/in.json" "all(p['fim_s'] > p['inicio_s'] for p in d['palavras'])")" "durações positivas"
  rm -rf "$d"
}

test_output_is_utf8_even_when_the_console_encoding_is_not() {
  local d; d="$(mktemp -d)"
  printf '%s' '{"idioma":"pt","segmentos":[{"inicio_s":0.3,"fim_s":2.4,"texto":"bagunçada hoje"}]}' > "$d/t.json"
  PYTHONUTF8=0 PYTHONIOENCODING=cp1252 python3 "$ROOT/scripts/to_remotion_input.py" "$d/t.json" v.mp4 > "$d/in.json" || _fail "conversão falhou"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); assert any('ç' in p['texto'] for p in d['palavras'])" "$d/in.json" || _fail "saída não é UTF-8 válido"
  rm -rf "$d"
}
