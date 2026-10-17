#!/usr/bin/env bash
# Testes de scripts/validate_schedule.py

NOW="2026-10-20T10:00:00-03:00"

# _mk <dir> <instruções python que alteram p> → grava <dir>/plan.json (e <dir>/v.mp4) a partir do plano válido
_mk() {
  mkdir -p "$1"; printf 'video de teste' > "$1/v.mp4"
  python3 - "$1/plan.json" "$2" <<'PY'
import json, sys
p = {"posts": [{"id": "p1", "video": "v.mp4", "legenda": "Rotina organizada com o Clo App ✨",
                "hashtags": ["#clo", "#produtividade"],
                "perfis": [{"rede": "instagram", "conta": "clo.app"}, {"rede": "tiktok", "conta": "clo.app"}],
                "data_hora": "2026-10-21T12:00:00-03:00"}]}
exec(sys.argv[2])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

# _check <dir> <instruções python> → saída do validador; status preservado
_check() {
  local out rc; _mk "$1" "$2"
  out=$(python3 "$ROOT/scripts/validate_schedule.py" "$1/plan.json" --now "$NOW" 2>&1); rc=$?
  printf '%s' "$out"; return "$rc"
}

test_valid_plan_passes() {
  local d; d="$(mktemp -d)"
  _check "$d" "pass" >/dev/null || _fail "plano válido foi rejeitado"
  rm -rf "$d"
}

test_past_or_too_soon_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['data_hora']='2026-10-19T12:00:00-03:00'") && _fail "passado aceito"
  assert_contains "$out" "data_hora" "mensagem"
  out=$(_check "$d" "p['posts'][0]['data_hora']='2026-10-20T10:10:00-03:00'") && _fail "10 min à frente aceito"
  assert_contains "$out" "15 minutos" "mensagem"
  _check "$d" "p['posts'][0]['data_hora']='2026-10-20T10:15:00-03:00'" >/dev/null || _fail "exatamente 15 min deveria passar"
  rm -rf "$d"
}

test_too_far_ahead_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['data_hora']='2026-11-25T12:00:00-03:00'") && _fail "mais de 30 dias aceito"
  assert_contains "$out" "30 dias" "mensagem"
  rm -rf "$d"
}

test_missing_timezone_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['data_hora']='2026-10-21T12:00:00'") && _fail "sem fuso aceito"
  assert_contains "$out" "-03:00" "mensagem"
  out=$(_check "$d" "p['posts'][0]['data_hora']='2026-10-21T12:00:00+00:00'") && _fail "fuso diferente aceito"
  assert_contains "$out" "-03:00" "mensagem"
  out=$(_check "$d" "p['posts'][0]['data_hora']='amanhã às 12'") && _fail "texto livre aceito"
  rm -rf "$d"
}

test_duplicate_or_empty_profiles_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['perfis']=[]") && _fail "perfis vazios aceitos"
  assert_contains "$out" "perfis" "mensagem"
  out=$(_check "$d" "p['posts'][0]['perfis']=[{'rede':'instagram','conta':'a'},{'rede':'instagram','conta':'a'}]") && _fail "perfil duplicado aceito"
  assert_contains "$out" "duplicado" "mensagem"
  rm -rf "$d"
}

test_unknown_network_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['perfis']=[{'rede':'orkut','conta':'a'}]") && _fail "rede desconhecida aceita"
  assert_contains "$out" "rede" "mensagem"
  rm -rf "$d"
}

test_missing_video_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['video']='nao-existe.mp4'") && _fail "vídeo inexistente aceito"
  assert_contains "$out" "não encontrado" "mensagem"
  rm -rf "$d"
}

test_unsafe_ids_rejected() {
  local d out id; d="$(mktemp -d)"
  for id in 'a b' '../x' '$(id)' '' 'a/b'; do
    out=$(_check "$d" "p['posts'][0]['id']=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$id")") && _fail "id inseguro aceito: '$id'"
    assert_contains "$out" "id" "mensagem ('$id')"
  done
  out=$(_check "$d" "p['posts'].append(dict(p['posts'][0]))") && _fail "ids repetidos aceitos"
  assert_contains "$out" "repetidos" "mensagem"
  out=$(_check "$d" "p['posts'].append(dict(p['posts'][0], id='P1'))") && _fail "ids que só diferem por maiúscula aceitos"
  rm -rf "$d"
}

test_bad_hashtags_rejected() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['hashtags']=['clo']") && _fail "hashtag sem # aceita"
  assert_contains "$out" "hashtag" "mensagem"
  out=$(_check "$d" "p['posts'][0]['hashtags']=['#com espaço']") && _fail "hashtag com espaço aceita"
  rm -rf "$d"
}

test_caption_length_limit() {
  local d out; d="$(mktemp -d)"
  out=$(_check "$d" "p['posts'][0]['legenda']='a'*3000") && _fail "legenda enorme aceita"
  assert_contains "$out" "legenda" "mensagem"
  rm -rf "$d"
}
