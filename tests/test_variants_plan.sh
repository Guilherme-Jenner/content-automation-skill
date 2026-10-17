#!/usr/bin/env bash
# Testes de scripts/validate_variants.py

_vv() { python3 "$ROOT/scripts/validate_variants.py" "$@"; }

# _mut <expressão python que altera d> → saída (stdout+stderr) do validador; status em $?
_mut() {
  local d out rc; d="$(mktemp -d)"
  python3 - "$ROOT/tests/data/variants_valid.json" "$d/v.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_vv "$d/v.json" 2>&1); rc=$?
  rm -rf "$d"; printf '%s' "$out"; return "$rc"
}

test_valid_plan_passes() {
  _vv "$ROOT/tests/data/variants_valid.json" >/dev/null 2>&1 || _fail "plano válido foi rejeitado"
}

test_quantity_out_of_range_rejected() {
  local out
  out=$(_mut "d['quantidade']=0") && _fail "0 deveria ser recusado"
  assert_contains "$out" "5" "mensagem cita o limite"
  out=$(_mut "d['quantidade']=6; d['variantes']+= [dict(d['variantes'][0], id=str(i), gancho='g%d'%i) for i in range(3,8)]") && _fail "6 deveria ser recusado"
  assert_contains "$out" "5" "mensagem cita o limite (6)"
}

test_quantity_must_match_variants() {
  local out; out=$(_mut "d['quantidade']=3") && _fail "deveria recusar"
  assert_contains "$out" "quantidade" "mensagem"
}

test_duplicate_hook_needs_justification() {
  local out
  out=$(_mut "d['variantes'][1]['gancho']=d['variantes'][0]['gancho']") && _fail "gancho repetido sem justificativa deveria ser recusado"
  assert_contains "$out" "gancho" "mensagem"
  _mut "v=d['variantes'][1]; v['gancho']=d['variantes'][0]['gancho']; v['gancho_repetido']=True; v['justificativa_gancho']='só há um gancho forte neste bruto'" >/dev/null \
    || _fail "gancho repetido justificado deveria passar"
}

test_overlapping_or_out_of_range_segments_rejected() {
  local out
  out=$(_mut "d['variantes'][0]['trechos']=[{'inicio_s':0,'fim_s':3},{'inicio_s':2,'fim_s':4}]") && _fail "sobreposição"
  assert_contains "$out" "sobrepõe" "mensagem"
  out=$(_mut "d['variantes'][0]['trechos']=[{'inicio_s':5,'fim_s':9}]") && _fail "fora da duração"
  assert_contains "$out" "fora da duração" "mensagem"
}

test_short_total_rejected() {
  local out; out=$(_mut "d['variantes'][0]['trechos']=[{'inicio_s':0,'fim_s':0.5}]") && _fail "total < 1 s deveria ser recusado"
  assert_contains "$out" "menos de 1 s" "mensagem"
}

test_redundant_variants_warn() {
  local d out; d="$(mktemp -d)"
  python3 - "$ROOT/tests/data/variants_valid.json" "$d/v.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["variantes"][1]["tipo"] = "trecho_diferente"
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_vv "$d/v.json" 2>&1) || _fail "redundância é aviso, não erro"
  assert_contains "$out" "aviso" "avisa a redundância"
  rm -rf "$d"
}

test_variant_without_findings_rejected() {
  local out; out=$(_mut "d['variantes'][0]['achados']=[]") && _fail "sem achados deveria ser recusado"
  assert_contains "$out" "achados" "mensagem"
}

test_non_numeric_quantity_rejected() {
  _mut "d['quantidade']='cinco'" >/dev/null && _fail "quantidade textual deveria ser recusada"
  return 0
}
