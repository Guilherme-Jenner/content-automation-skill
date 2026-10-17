#!/usr/bin/env bash
# Testes de scripts/captions_to_transcript.py (legendas do modo gerado, por cena)

_ct() { python3 "$ROOT/scripts/captions_to_transcript.py" "$@"; }

# _prep <dir> [duração real do clipe c1] → gen-plan (c1 4 s, c2 5 s, c3 6 s) + clipes reais + manifesto
_prep() {
  local d="$1" d1="${2:-4}" id cor dur
  mkdir -p "$d/w/clips"
  python3 - "$d/g.json" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}, {"id": "c3", "prompt": "c", "duracao_s": 6}]},
          open(sys.argv[1], "w", encoding="utf-8"))
PY
  for pair in "c1 red $d1" "c2 green 5" "c3 blue 6"; do
    read -r id cor dur <<EOP
$pair
EOP
    ffmpeg -v error -y -f lavfi -i "color=c=$cor:size=480x854:rate=25:duration=$dur" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/$id.mp4" </dev/null
    python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" "$id" "clips/$id.mp4" 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key "$id")" fake >/dev/null
  done
}

# _caps <dir> <instruções python que alteram p> → grava $d/c.json
_caps() {
  python3 - "$1/c.json" "$2" <<'PY'
import json, sys
p = {"estilo": "padrao", "cenas": [
    {"cena": "c1", "legendas": [{"texto": "Sua rotina vive bagunçada?"}]},
    {"cena": "c2", "legendas": [{"texto": "O Clo App organiza tudo", "inicio_s": 0.5, "fim_s": 3}]}]}
exec(sys.argv[2])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
_run() { _ct "$1/c.json" "$1/g.json" "$1/w/clips-manifest.json"; }

test_offsets_follow_the_real_clip_durations() {
  local d; d="$(mktemp -d)"; _prep "$d" 4.5; _caps "$d" "pass"
  _run "$d" > "$d/t.json" 2>/dev/null || _fail "conversão falhou"
  assert_eq 2 "$(json_get "$d/t.json" "len(d['segmentos'])")" "2 legendas"
  assert_near 5.0 "$(json_get "$d/t.json" "d['segmentos'][1]['inicio_s']")" 0.15 "c2 começa em 4,5 (duração REAL de c1) + 0,5"
  assert_near 7.5 "$(json_get "$d/t.json" "d['segmentos'][1]['fim_s']")" 0.15 "4,5 + 3"
  rm -rf "$d"
}

test_default_timing_covers_the_scene() {
  local d; d="$(mktemp -d)"; _prep "$d"; _caps "$d" "pass"
  _run "$d" > "$d/t.json" 2>/dev/null
  assert_near 0.2 "$(json_get "$d/t.json" "d['segmentos'][0]['inicio_s']")" 0.01 "início padrão"
  assert_near 3.8 "$(json_get "$d/t.json" "d['segmentos'][0]['fim_s']")" 0.15 "fim padrão = duração − 0,2"
  rm -rf "$d"
}

test_output_validates_as_transcript_and_is_ordered() {
  local d; d="$(mktemp -d)"; _prep "$d"; _caps "$d" "p['cenas'].reverse()"   # cenas fora de ordem no plano de legendas
  _run "$d" > "$d/t.json" 2>/dev/null || _fail "conversão falhou"
  python3 "$ROOT/scripts/validate_json.py" "$ROOT/schemas/transcript.schema.json" "$d/t.json" || _fail "fora do schema transcript"
  assert_eq True "$(json_get "$d/t.json" "d['segmentos'][0]['inicio_s'] < d['segmentos'][1]['inicio_s']")" "segmentos em ordem de tempo"
  rm -rf "$d"
}

test_invalid_captions_are_rejected() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  _caps "$d" "p['cenas'][0]['cena']='c9'"; out=$(_run "$d" 2>&1) && _fail "cena inexistente aceita"; assert_contains "$out" "c9" "cena inexistente"
  python3 "$ROOT/scripts/clips_manifest.py" show "$d/w/clips-manifest.json" >/dev/null
  _caps "$d" "p['cenas'].append({'cena':'c3','legendas':[{'texto':'x y z'}]})"
  python3 - "$d/w/clips-manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8")); del m["clips"]["c3"]
json.dump(m, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(_run "$d" 2>&1) && _fail "cena sem clipe no manifesto aceita"; assert_contains "$out" "manifesto" "sem clipe"
  rm -rf "$d"; d="$(mktemp -d)"; _prep "$d"
  _caps "$d" "p['cenas'][0]['legendas'][0]['texto']='   '"; out=$(_run "$d" 2>&1) && _fail "texto vazio aceito"; assert_contains "$out" "texto" "texto vazio"
  _caps "$d" "p['cenas'][0]['legendas'][0]['texto']='x'*58"; out=$(_run "$d" 2>&1) && _fail "texto grande aceito"; assert_contains "$out" "51" "texto grande (referência do estilo padrao)"
  _caps "$d" "p['cenas'][1]['legendas'][0].update(inicio_s=2, fim_s=1)"; out=$(_run "$d" 2>&1) && _fail "fim antes do início aceito"; assert_contains "$out" "fim_s" "fim antes do início"
  _caps "$d" "p['cenas'][1]['legendas'][0].update(inicio_s=1, fim_s=1.5)"; out=$(_run "$d" 2>&1) && _fail "legenda curta aceita"; assert_contains "$out" "0,8" "legenda curta"
  _caps "$d" "p['cenas'][1]['legendas'][0].update(inicio_s=0, fim_s=9)"; out=$(_run "$d" 2>&1) && _fail "fora da cena aceito"; assert_contains "$out" "fora da cena" "fora da cena"
  _caps "$d" "p['cenas'][1]['legendas']=[{'texto':'a b','inicio_s':0,'fim_s':2},{'texto':'c d','inicio_s':1,'fim_s':3}]"; out=$(_run "$d" 2>&1) && _fail "sobreposição aceita"; assert_contains "$out" "sobrep" "sobreposição"
  _caps "$d" "p['cenas'][0]['legendas']=[{'texto':'t%d' % i,'inicio_s':0.2,'fim_s':3.8} for i in range(41)]"; out=$(_run "$d" 2>&1) && _fail "41 legendas aceitas"; assert_contains "$out" "40" "limite"
  _caps "$d" "p['estilo']='neon'"; out=$(_run "$d" 2>&1) && _fail "estilo desconhecido aceito"; assert_contains "$out" "estilo" "estilo"
  rm -rf "$d"
}

test_special_characters_survive() {
  local d; d="$(mktemp -d)"; _prep "$d"
  _caps "$d" "p['cenas'][0]['legendas'][0]['texto']='Ação \"rápida\" {ok} \\\\N d\\'água 🚀'"
  _run "$d" > "$d/t.json" 2>/dev/null || _fail "conversão falhou"
  assert_eq 'Ação "rápida" {ok} \N d'"'"'água 🚀' "$(json_get "$d/t.json" "d['segmentos'][0]['texto']")" "texto preservado exatamente"
  rm -rf "$d"
}

test_style_option() {
  local d; d="$(mktemp -d)"; _prep "$d"; _caps "$d" "p['estilo']='destaque'"
  assert_eq destaque "$(_ct "$d/c.json" "$d/g.json" "$d/w/clips-manifest.json" --estilo)" "estilo do plano"
  rm -rf "$d"
}
