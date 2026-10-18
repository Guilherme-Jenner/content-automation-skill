#!/usr/bin/env bash
# Testes de scripts/validate_gen_variants.py e scripts/gen_variant_info.py (variantes do modo gerado)

_gv() { python3 "$ROOT/scripts/validate_gen_variants.py" "$@"; }
_gi() { python3 "$ROOT/scripts/gen_variant_info.py" "$@"; }

# _plans <dir> [expressão python que altera p] → grava $d/g.json (gen-plan c1 4s, c2 5s, c3 6s) e $d/v.json
_plans() {
  python3 - "$1" "${2:-pass}" <<'PY'
import json, os, sys
d = sys.argv[1]
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}, {"id": "c3", "prompt": "c", "duracao_s": 6}]},
          open(os.path.join(d, "g.json"), "w", encoding="utf-8"))
p = {"quantidade": 2, "variantes": [
    {"id": "A", "cenas": ["c1", "c2", "c3"], "aprovada": True, "achados": ["pergunta no início retém mais"],
     "legendas": {"estilo": "padrao", "cenas": [{"cena": "c1", "legendas": [{"texto": "Sua rotina vive bagunçada?"}]},
                                                  {"cena": "c2", "legendas": [{"texto": "O Clo App organiza tudo"}]}]}},
    {"id": "B", "cenas": ["c3", "c1"], "aprovada": True, "achados": ["resultado primeiro"],
     "legendas": {"estilo": "destaque", "cenas": [{"cena": "c3", "legendas": [{"texto": "Tudo em um lugar só"}]}]}}]}
exec(sys.argv[2])
json.dump(p, open(os.path.join(d, "v.json"), "w", encoding="utf-8"), ensure_ascii=False)
PY
}
# _bad <expressão> → saída do validador; status 1 esperado
_bad() { local d out rc; d="$(mktemp -d)"; _plans "$d" "$1"; out=$(_gv "$d/v.json" "$d/g.json" 2>&1); rc=$?; rm -rf "$d"; printf '%s' "$out"; return "$rc"; }

test_valid_plan_passes() {
  local d; d="$(mktemp -d)"; _plans "$d"
  _gv "$d/v.json" "$d/g.json" >/dev/null 2>&1 || _fail "plano válido recusado"
  rm -rf "$d"
}

test_unknown_scene_and_duplicates_rejected() {
  local out
  out=$(_bad "p['variantes'][0]['cenas']=['c1','c9']") && _fail "cena inexistente aceita"; assert_contains "$out" "c9" "cena inexistente"
  out=$(_bad "p['variantes'][0]['cenas']=['c1','c2','c1']") && _fail "cena repetida aceita"; assert_contains "$out" "repet" "cena repetida na variante"
  out=$(_bad "p['variantes'][0]['cenas']=[]") && _fail "variante sem cenas aceita"
}

test_captions_must_refer_to_scenes_of_the_variant() {
  local out
  out=$(_bad "p['variantes'][1]['legendas']['cenas'].append({'cena':'c2','legendas':[{'texto':'x y'}]})") && _fail "legenda de cena fora da variante aceita"
  assert_contains "$out" "c2" "cena fora da variante"
}

test_quantity_limits_and_match() {
  local out
  out=$(_bad "p['quantidade']=3") && _fail "quantidade diferente aceita"; assert_contains "$out" "quantidade" "mensagem"
  out=$(_bad "p['variantes']+=[dict(p['variantes'][0], id='X%d'%i, cenas=['c%d'%(1+i%3)], legendas={'estilo':'padrao','cenas':[{'cena':'c%d'%(1+i%3),'legendas':[{'texto':'g%d'%i}]}]}) for i in range(4)]; p['quantidade']=6") && _fail "6 variantes aceitas"
  assert_contains "$out" "5" "limite"
}

test_ids_must_be_safe_and_unique() {
  local out
  out=$(_bad "p['variantes'][0]['id']='a/../b'") && _fail "id inseguro aceito"; assert_contains "$out" "id" "id"
  out=$(_bad "p['variantes'][1]['id']='a'; p['variantes'][0]['id']='A'") && _fail "ids que só diferem na caixa aceitos"; assert_contains "$out" "repetid" "ids repetidos"
}

test_hook_is_derived_and_must_differ() {
  local out
  out=$(_bad "p['variantes'][1]['cenas']=['c1','c3']; p['variantes'][1]['legendas']['cenas']=[{'cena':'c1','legendas':[{'texto':'sua rotina vive bagunçada?'}]}]") && _fail "gancho repetido sem justificativa aceito"
  assert_contains "$out" "gancho" "mensagem"
  _bad "p['variantes'][1]['cenas']=['c1','c3']; v=p['variantes'][1]; v['legendas']['cenas']=[{'cena':'c1','legendas':[{'texto':'Sua rotina vive bagunçada?'}]}]; v['gancho_repetido']=True; v['justificativa_gancho']='só há um gancho forte'" >/dev/null \
    || _fail "gancho repetido com justificativa deveria passar"
}

test_identical_variants_and_missing_findings_rejected() {
  local out
  out=$(_bad "p['variantes'][1]=dict(p['variantes'][0], id='B')") && _fail "variante idêntica aceita"
  assert_contains "$out" "idêntic" "idêntica"
  out=$(_bad "p['variantes'][0]['achados']=[]") && _fail "sem achados aceito"; assert_contains "$out" "achados" "achados"
}

test_music_fields_validated() {
  local out
  out=$(_bad "p['variantes'][0]['volume_db']=5") && _fail "volume positivo aceito"; assert_contains "$out" "volume" "volume"
  _bad "p['variantes'][0]['musica']='m.wav'; p['variantes'][0]['volume_db']=-12" >/dev/null || _fail "música e volume válidos recusados"
}

test_info_derives_plan_in_the_variant_order_with_same_budget_keys() {
  local d; d="$(mktemp -d)"; _plans "$d"
  _gi "$d/v.json" list > "$d/l.txt"
  assert_eq "A sim" "$(sed -n 1p "$d/l.txt")" "lista A"; assert_eq "B sim" "$(sed -n 2p "$d/l.txt")" "lista B"
  _gi "$d/v.json" genplan "$d/g.json" B > "$d/gB.json" || _fail "genplan falhou"
  assert_eq "c3 c1" "$(python3 "$ROOT/scripts/genplan_info.py" "$d/gB.json" list | tr '\n' ' ' | sed 's/ $//')" "ordem da variante"
  assert_eq "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key c3)" "$(python3 "$ROOT/scripts/genplan_info.py" "$d/gB.json" key c3)" "mesma chave do clipe"
  python3 "$ROOT/scripts/validate_genplan.py" "$d/gB.json" || _fail "plano derivado inválido"
  _gi "$d/v.json" captions B > "$d/cB.json" || _fail "captions falhou"
  assert_eq destaque "$(json_get "$d/cB.json" "d['estilo']")" "estilo da variante"
  assert_eq "-" "$(_gi "$d/v.json" music A)" "sem música"
  rm -rf "$d"
}

test_info_music_resolves_relative_to_the_plan() {
  local d; d="$(mktemp -d)"; _plans "$d" "p['variantes'][0]['musica']='sub/m.wav'; p['variantes'][0]['volume_db']=-12"
  local m; m="$(_gi "$d/v.json" music A)"
  assert_contains "$m" "m.wav" "arquivo"
  assert_contains "$m" "$(basename "$d")" "dentro da pasta do plano"
  assert_eq "-12" "$(_gi "$d/v.json" volume A)" "volume declarado"
  assert_eq "-" "$(_gi "$d/v.json" volume B)" "sem volume declarado"
  rm -rf "$d"
}

test_id_with_trailing_newline_is_rejected() {
  local out
  out=$(_bad "p['variantes'][1]['id']='B\n'") && _fail "id com quebra de linha aceito"; assert_contains "$out" "id" "mensagem"
}

test_hook_is_the_caption_that_appears_first_in_time() {
  local out
  out=$(_bad "p['variantes'][1]['cenas']=['c1','c3']; p['variantes'][1]['legendas']['cenas']=[{'cena':'c1','legendas':[{'texto':'Outro texto qualquer','inicio_s':2,'fim_s':3.5},{'texto':'Sua rotina vive bagunçada?','inicio_s':0.2,'fim_s':1.5}]}]") && _fail "gancho igual (o primeiro NO TEMPO) aceito"
  assert_contains "$out" "gancho" "mensagem"
}

test_volume_without_music_and_unknown_fields_are_rejected() {
  local out
  out=$(_bad "p['variantes'][0]['volume_db']=-12") && _fail "volume sem música aceito"; assert_contains "$out" "volume_db" "mensagem"
  out=$(_bad "p['variantes'][0]['musicas']='m.wav'") && _fail "campo desconhecido aceito"; assert_contains "$out" "musicas" "cita o campo"
  out=$(_bad "p['extra']=1") && _fail "campo desconhecido no topo aceito"; assert_contains "$out" "extra" "cita o campo do topo"
}

test_music_must_stay_inside_the_plan_folder_when_relative() {
  local out
  out=$(_bad "p['variantes'][0]['musica']='../outra/m.wav'") && _fail "música fora da pasta do plano aceita"
  assert_contains "$out" "pasta do plano" "mensagem"
}

test_posix_absolute_music_path_is_refused_on_windows() {
  [ "${OS:-}" = Windows_NT ] || return 0
  local out
  out=$(_bad "p['variantes'][0]['musica']='/tmp/m.wav'") && _fail "caminho POSIX absoluto aceito no Windows"
  assert_contains "$out" "C:/" "orienta o formato"
}

test_skill_describes_the_hook_as_the_first_caption_in_time() {
  assert_contains "$(cat "$ROOT/skills/edit-generated/SKILL.md")" "que aparece primeiro" "texto alinhado ao código"
}
