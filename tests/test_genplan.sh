#!/usr/bin/env bash
# Testes de scripts/storyboard_to_genplan.py e scripts/validate_genplan.py

_conv() { python3 "$ROOT/scripts/storyboard_to_genplan.py" "$@"; }
_val() { python3 "$ROOT/scripts/validate_genplan.py" "$@"; }

# _mut <expressão python que altera p> → grava $d/g.json a partir do plano válido e valida; imprime a saída
_mut() {
  local d out rc; d="$(mktemp -d)"
  python3 - "$d/g.json" "$1" <<'PY'
import json, sys
p = {"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "720p", "audio": False,
     "cenas": [{"id": "c1", "prompt": "pessoa olhando o celular", "duracao_s": 5},
               {"id": "c2", "prompt": "tela do app", "duracao_s": 8}]}
exec(sys.argv[2])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_val "$d/g.json" 2>&1); rc=$?
  rm -rf "$d"; printf '%s' "$out"; return "$rc"
}

test_converts_generated_storyboard() {
  local d; d="$(mktemp -d)"
  _conv "$ROOT/tests/data/storyboard_gerado.json" > "$d/g.json" 2>/dev/null || _fail "conversão falhou"
  assert_eq "seedance_2_5" "$(json_get "$d/g.json" "d['modelo']")" "modelo"
  assert_eq "9:16" "$(json_get "$d/g.json" "d['aspecto']")" "aspecto"
  assert_eq 4 "$(json_get "$d/g.json" "len(d['cenas'])")" "4 cenas"
  assert_eq "pessoa olhando o celular, luz natural, vertical 9:16" "$(json_get "$d/g.json" "d['cenas'][0]['prompt']")" "prompt vem do storyboard"
  _val "$d/g.json" 2>&1 || _fail "o plano convertido deveria validar"
  rm -rf "$d"
}

test_short_scene_is_raised_to_4_with_warning() {
  local d err; d="$(mktemp -d)"
  err=$(_conv "$ROOT/tests/data/storyboard_gerado.json" 2>&1 >"$d/g.json")
  assert_eq 4 "$(json_get "$d/g.json" "d['cenas'][0]['duracao_s']")" "3 s vira 4 s"
  assert_eq 9 "$(json_get "$d/g.json" "d['cenas'][1]['duracao_s']")" "9 s continua 9 s"
  assert_contains "$err" "c1" "aviso cita a cena"
  assert_contains "$err" "de 3 para 4" "aviso explica o ajuste"
  rm -rf "$d"
}

test_fractional_duration_rounds_up() {
  local d; d="$(mktemp -d)"
  python3 - "$d/s.json" <<'PY'
import json, sys
json.dump({"titulo": "t", "duracao_alvo_s": 10, "modo": "gerado",
           "cenas": [{"id": "a", "descricao": "x", "duracao_s": 5.2, "prompt": "p1"}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  _conv "$d/s.json" > "$d/g.json" 2>/dev/null || _fail "conversão falhou"
  assert_eq 6 "$(json_get "$d/g.json" "d['cenas'][0]['duracao_s']")" "5,2 s sobe para 6 s"
  rm -rf "$d"
}

test_recorded_storyboard_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_conv "$ROOT/tests/data/shot_list_gravado.json" 2>&1) && _fail "shot list do modo gravado não gera clipes"
  assert_contains "$out" "gerado" "mensagem"
  rm -rf "$d"
}

test_scene_without_prompt_is_rejected_by_converter() {
  local d out; d="$(mktemp -d)"
  python3 - "$d/s.json" <<'PY'
import json, sys
json.dump({"titulo": "t", "duracao_alvo_s": 10, "modo": "gerado",
           "cenas": [{"id": "a", "descricao": "sem prompt", "duracao_s": 5}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(_conv "$d/s.json" 2>&1) && _fail "cena sem prompt aceita"
  assert_contains "$out" "prompt" "mensagem"
  rm -rf "$d"
}

test_validator_rejects_bad_plans() {
  local out
  _mut "pass" >/dev/null || _fail "plano válido rejeitado"
  out=$(_mut "p['cenas'][0]['prompt']='  '") && _fail "prompt vazio aceito"; assert_contains "$out" "prompt" "prompt"
  out=$(_mut "p['cenas'][0]['duracao_s']=31") && _fail "31 s aceito"; assert_contains "$out" "duracao_s" "duração alta"
  out=$(_mut "p['cenas'][0]['duracao_s']=3") && _fail "3 s aceito"; assert_contains "$out" "duracao_s" "duração baixa"
  out=$(_mut "p['cenas'][0]['duracao_s']=5.5") && _fail "duração fracionária aceita"; assert_contains "$out" "duracao_s" "duração fracionária"
  out=$(_mut "p['resolucao']='4k'") && _fail "resolução 4k aceita"; assert_contains "$out" "resolucao" "resolução"
  out=$(_mut "p['cenas']=[dict(id='c%d' % i, prompt='x', duracao_s=5) for i in range(13)]") && _fail "13 cenas aceitas"; assert_contains "$out" "12" "limite de cenas"
  out=$(_mut "p['cenas'][1]['id']='C1'") && _fail "ids repetidos aceitos"; assert_contains "$out" "repetidos" "ids repetidos"
  out=$(_mut "p['cenas'][0]['id']='a b'") && _fail "id inseguro aceito"; assert_contains "$out" "id" "id inseguro"
  out=$(_mut "p['cenas'][0]['prompt']='x'*4001") && _fail "prompt enorme aceito"; assert_contains "$out" "4000" "limite do prompt"
  out=$(_mut "p['modelo']='outro'") && _fail "modelo desconhecido aceito"; assert_contains "$out" "modelo" "modelo"
}

test_default_resolution_and_audio_off() {
  local d; d="$(mktemp -d)"
  _conv "$ROOT/tests/data/storyboard_gerado.json" > "$d/g.json" 2>/dev/null
  assert_eq "720p" "$(json_get "$d/g.json" "d['resolucao']")" "resolução padrão"
  assert_eq "False" "$(json_get "$d/g.json" "d['audio']")" "áudio desligado por padrão"
  _conv "$ROOT/tests/data/storyboard_gerado.json" --resolucao 1080p --audio > "$d/h.json" 2>/dev/null
  assert_eq "1080p" "$(json_get "$d/h.json" "d['resolucao']")" "resolução escolhida"
  assert_eq "True" "$(json_get "$d/h.json" "d['audio']")" "áudio ligado"
  rm -rf "$d"
}
