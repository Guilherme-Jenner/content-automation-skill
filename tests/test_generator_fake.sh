#!/usr/bin/env bash
# Testes de scripts/generators/fake.sh e scripts/genplan_info.py

_gf() { bash "$ROOT/scripts/generators/fake.sh" "$@"; }
_info() { python3 "$ROOT/scripts/genplan_info.py" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
_dims() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$1"; }

# _plan <arquivo> <resolucao> <audio true|false>
_plan() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": sys.argv[2], "audio": sys.argv[3] == "true",
           "cenas": [{"id": "c1", "prompt": "pessoa olhando o celular", "duracao_s": 5},
                     {"id": "c2", "prompt": "tela do app", "duracao_s": 4}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
}

test_quote_depends_on_resolution_and_audio() {
  local d; d="$(mktemp -d)"
  _plan "$d/g.json" 480p false; assert_eq 5 "$(_gf quote "$d/g.json" c1)" "480p: 1 crédito/s"
  _plan "$d/g.json" 720p false; assert_eq 10 "$(_gf quote "$d/g.json" c1)" "720p: 2 créditos/s"
  _plan "$d/g.json" 1080p false; assert_eq 20 "$(_gf quote "$d/g.json" c1)" "1080p: 4 créditos/s"
  _plan "$d/g.json" 720p true; assert_eq 12 "$(_gf quote "$d/g.json" c1)" "áudio: +20%"
  rm -rf "$d"
}

test_run_creates_a_clip_with_the_right_shape() {
  local d cost; d="$(mktemp -d)"; _plan "$d/g.json" 480p false
  cost=$(_gf run "$d/g.json" c1 "$d/c1.mp4") || _fail "run falhou"
  assert_eq 5 "$cost" "custo efetivo = cotação"
  assert_near 5 "$(_dur "$d/c1.mp4")" 0.2 "duração da cena"
  assert_eq "480x854" "$(_dims "$d/c1.mp4")" "proporção vertical 9:16 em 480p"
  assert_eq "" "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$d/c1.mp4")" "sem áudio"
  _plan "$d/g.json" 480p true
  _gf run "$d/g.json" c2 "$d/c2.mp4" >/dev/null || _fail "run com áudio falhou"
  assert_eq audio "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$d/c2.mp4")" "com áudio"
  rm -rf "$d"
}

test_overrun_doubles_the_effective_cost() {
  local d cost; d="$(mktemp -d)"; _plan "$d/g.json" 480p false
  cost=$(CLO_GEN_FAKE_OVERRUN=c1 _gf run "$d/g.json" c1 "$d/c1.mp4") || _fail "run falhou"
  assert_eq 10 "$cost" "custo dobrado"
  cost=$(CLO_GEN_FAKE_OVERRUN=c1 _gf run "$d/g.json" c2 "$d/c2.mp4") || _fail "run falhou"
  assert_eq 4 "$cost" "outra cena não é afetada"
  rm -rf "$d"
}

test_unknown_or_unsafe_scene_rejected() {
  local d; d="$(mktemp -d)"; _plan "$d/g.json" 480p false
  _gf quote "$d/g.json" nao-existe >/dev/null 2>&1 && _fail "cena inexistente aceita"
  _gf run "$d/g.json" '../x' "$d/x.mp4" >/dev/null 2>&1 && _fail "id inseguro aceito"
  [ ! -e "$d/x.mp4" ] || _fail "não deveria criar arquivo"
  rm -rf "$d"
}

test_fake_generator_never_touches_the_network() {
  ! grep -Eq '\b(curl|wget|nc|ssh|http://|https://)' "$ROOT/scripts/generators/fake.sh" || _fail "o gerador falso não pode usar rede"
}

test_scene_key_changes_with_anything_that_costs_money() {
  local d k1 k2; d="$(mktemp -d)"; _plan "$d/g.json" 720p false
  k1=$(_info "$d/g.json" key c1)
  assert_eq "$k1" "$(_info "$d/g.json" key c1)" "estável"
  case "$k1" in clip-c1-????????) ;; *) _fail "formato da chave inesperado: $k1" ;; esac
  _plan "$d/h.json" 1080p false; k2=$(_info "$d/h.json" key c1)
  [ "$k1" != "$k2" ] || _fail "a resolução deveria mudar a chave"
  _plan "$d/i.json" 720p true; k2=$(_info "$d/i.json" key c1)
  [ "$k1" != "$k2" ] || _fail "o áudio deveria mudar a chave"
  python3 - "$d/g.json" "$d/j.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"][0]["prompt"] = "outro prompt"
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  k2=$(_info "$d/j.json" key c1)
  [ "$k1" != "$k2" ] || _fail "o prompt deveria mudar a chave"
  assert_eq "c1
c2" "$(_info "$d/g.json" list)" "lista na ordem do plano"
  rm -rf "$d"
}
