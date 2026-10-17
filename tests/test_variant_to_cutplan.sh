#!/usr/bin/env bash
# Testes de scripts/variant_to_cutplan.py

_vc() { python3 "$ROOT/scripts/variant_to_cutplan.py" "$@"; }

_make() { # <saida> <aprovada1> <aprovada2>
  python3 - "$ROOT/tests/data/variants_valid.json" "$1" "$2" "$3" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["variantes"][0]["trechos"] = [{"inicio_s": 1, "fim_s": 3}, {"inicio_s": 4, "fim_s": 6}]
d["variantes"][0]["aprovada"] = sys.argv[3] == "true"
d["variantes"][1]["aprovada"] = sys.argv[4] == "true"
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_complement_of_segments() {
  local d; d="$(mktemp -d)"; _make "$d/v.json" true false
  _vc "$d/v.json" 1 pasta/video.mp4 > "$d/c.json" || _fail "conversão falhou"
  assert_eq 3 "$(json_get "$d/c.json" "len(d['cortes'])")" "3 cortes"
  assert_eq "[(0.0, 1.0), (3.0, 4.0), (6.0, 6.5)]" "$(json_get "$d/c.json" "[(float(c['inicio_s']), float(c['fim_s'])) for c in d['cortes']]")" "complemento"
  assert_eq "pasta/video.mp4" "$(json_get "$d/c.json" "d['video']")" "vídeo"
  assert_near 6.5 "$(json_get "$d/c.json" "d['duracao_s']")" 0.001 "duração"
  rm -rf "$d"
}

test_approval_is_per_variant() {
  local d; d="$(mktemp -d)"; _make "$d/v.json" true false
  _vc "$d/v.json" 1 v.mp4 > "$d/c1.json"; _vc "$d/v.json" 2 v.mp4 > "$d/c2.json"
  assert_eq True "$(json_get "$d/c1.json" "d['approved']")" "variante 1 aprovada"
  assert_eq False "$(json_get "$d/c2.json" "d['approved']")" "variante 2 não aprovada"
  rm -rf "$d"
}

test_unknown_id_fails() {
  local d msg; d="$(mktemp -d)"; _make "$d/v.json" true true
  msg=$(_vc "$d/v.json" 9 v.mp4 2>&1) && _fail "id inexistente deveria falhar"
  assert_contains "$msg" "9" "cita o id"
  rm -rf "$d"
}

test_result_validates_with_validate_cutplan() {
  local d; d="$(mktemp -d)"; _make "$d/v.json" true true
  _vc "$d/v.json" 1 v.mp4 > "$d/c.json"
  python3 "$ROOT/scripts/validate_cutplan.py" "$d/c.json" || _fail "plano gerado é inválido"
  rm -rf "$d"
}

test_merges_silence_cuts_into_the_plan() {
  local d; d="$(mktemp -d)"; _make "$d/v.json" true true
  # trechos mantidos: [1,3] e [4,6]; silêncio em [2.2,2.8] (dentro de um trecho) e [2.5,3.5] (encosta no corte [3,4])
  printf '{"video":"v.mp4","duracao_s":6.5,"approved":false,"cortes":[{"inicio_s":2.2,"fim_s":2.8,"motivo":"silêncio"},{"inicio_s":2.5,"fim_s":3.5,"motivo":"silêncio"}]}' > "$d/s.json"
  _vc "$d/v.json" 1 v.mp4 --merge "$d/s.json" > "$d/c.json" || _fail "conversão com merge falhou"
  assert_eq "[(0.0, 1.0), (2.2, 4.0), (6.0, 6.5)]" "$(json_get "$d/c.json" "[(float(c['inicio_s']), float(c['fim_s'])) for c in d['cortes']]")" "união sem sobreposição"
  python3 "$ROOT/scripts/validate_cutplan.py" "$d/c.json" || _fail "plano com merge inválido"
  rm -rf "$d"
}
