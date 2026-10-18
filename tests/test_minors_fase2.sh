#!/usr/bin/env bash
# Minors adiados da fase 2 (ledger): hashtags repetidas, @conta, horários repetidos, pasta temporária do pacote

_NOW="2026-10-20T10:00:00-03:00"

# _plan <dir> <instruções python sobre p>
_plan() {
  mkdir -p "$1"; printf 'video de teste' > "$1/v.mp4"
  python3 - "$1/plan.json" "$2" <<'PY'
import json, sys
p = {"posts": [{"id": "p1", "video": "v.mp4", "legenda": "Rotina organizada com o Clo App",
                "hashtags": ["#clo", "#produtividade"],
                "perfis": [{"rede": "instagram", "conta": "clo.app"}, {"rede": "tiktok", "conta": "clo.app"}],
                "data_hora": "2026-10-21T12:00:00-03:00"}]}
exec(sys.argv[2])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_repeated_hashtags_are_refused_ignoring_case() {
  local d out; d="$(mktemp -d)"; _plan "$d" "p['posts'][0]['hashtags']=['#Clo','#clo']"
  out=$(python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$_NOW" 2>&1) && _fail "hashtags repetidas aceitas"
  assert_contains "$out" "repetid" "mensagem"
  rm -rf "$d"
}

test_at_sign_does_not_make_a_profile_different() {
  local d out; d="$(mktemp -d)"; _plan "$d" "p['posts'][0]['perfis']=[{'rede':'instagram','conta':'@clo.app'},{'rede':'instagram','conta':'clo.app'}]"
  out=$(python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$_NOW" 2>&1) && _fail "@clo.app e clo.app tratados como perfis diferentes"
  assert_contains "$out" "duplicado" "mensagem"
  rm -rf "$d"
}

test_repeated_times_in_cadence_do_not_repeat_slots() {
  local d out; d="$(mktemp -d)"
  printf '%s' '{"dias":["qua","sex"],"horarios":["12:00","12:00"],"minimo_entre_posts_h":0}' > "$d/c.json"
  out=$(python3 "$ROOT/scripts/propose_slots.py" "$d/c.json" 3 --now "$_NOW") || _fail "falhou"
  assert_eq 3 "$(printf '%s\n' "$out" | sort -u | wc -l | tr -d ' ')" "três horários distintos"
  rm -rf "$d"
}

test_export_does_not_touch_a_foreign_hidden_folder() {
  local d; d="$(mktemp -d)"; _plan "$d" "pass"
  mkdir -p "$d/out/.p1.tmp"; printf 'meu' > "$d/out/.p1.tmp/arquivo"
  bash "$ROOT/scripts/export_package.sh" "$d/plan.json" p1 "$d/out" --now "$_NOW" >/dev/null 2>&1 || _fail "export falhou"
  assert_file_exists "$d/out/.p1.tmp/arquivo"
  assert_file_exists "$d/out/p1/video.mp4"
  [ -z "$(find "$d/out" -maxdepth 1 -name '.p1.*' ! -name '.p1.tmp' | head -1)" ] || _fail "sobrou pasta temporária do export"
  rm -rf "$d"
}
