#!/usr/bin/env bash
# Testes de scripts/propose_slots.py

NOW="2026-10-20T10:00:00-03:00"   # terça-feira

_ps() { python3 "$ROOT/scripts/propose_slots.py" "$@"; }

# _cad <arquivo> <json>
_cad() { printf '%s' "$2" > "$1"; }

CAD='{"dias":["seg","qua","sex"],"horarios":["12:00","19:00"],"minimo_entre_posts_h":6}'

test_slots_follow_days_and_times() {
  local d out; d="$(mktemp -d)"; _cad "$d/c.json" "$CAD"
  out=$(_ps "$d/c.json" 4 --now "$NOW") || _fail "propose_slots falhou"
  assert_eq "2026-10-21T12:00:00-03:00
2026-10-21T19:00:00-03:00
2026-10-23T12:00:00-03:00
2026-10-23T19:00:00-03:00" "$out" "quarta e sexta, 12:00 e 19:00"
  rm -rf "$d"
}

test_slots_are_increasing_and_spaced() {
  local d out; d="$(mktemp -d)"
  _cad "$d/c.json" '{"dias":["seg","qua","sex"],"horarios":["12:00","19:00"],"minimo_entre_posts_h":8}'
  out=$(_ps "$d/c.json" 4 --now "$NOW") || _fail "propose_slots falhou"
  assert_eq "2026-10-21T12:00:00-03:00
2026-10-23T12:00:00-03:00
2026-10-26T12:00:00-03:00
2026-10-28T12:00:00-03:00" "$out" "19:00 fica 7h depois de 12:00 (< 8h) e é pulado"
  rm -rf "$d"
}

test_never_in_the_past_or_too_soon() {
  local d out; d="$(mktemp -d)"; _cad "$d/c.json" "$CAD"
  out=$(_ps "$d/c.json" 1 --now "2026-10-21T11:50:00-03:00") || _fail "propose_slots falhou"
  assert_eq "2026-10-21T19:00:00-03:00" "$out" "12:00 está a 10 min: pulado"
  out=$(_ps "$d/c.json" 1 --now "2026-10-21T11:45:00-03:00") || _fail "propose_slots falhou"
  assert_eq "2026-10-21T12:00:00-03:00" "$out" "exatamente 15 min à frente é aceito"
  rm -rf "$d"
}

test_not_enough_slots_fails_clearly() {
  local d out; d="$(mktemp -d)"
  _cad "$d/c.json" '{"dias":["seg"],"horarios":["12:00"],"minimo_entre_posts_h":0}'
  out=$(_ps "$d/c.json" 10 --now "$NOW" 2>&1) && _fail "10 posts em 30 dias com 1 slot por semana deveria falhar"
  assert_contains "$out" "30 dias" "mensagem"
  rm -rf "$d"
}

test_invalid_cadence_or_count_rejected() {
  local d c; d="$(mktemp -d)"
  for c in '{"dias":["xyz"],"horarios":["12:00"],"minimo_entre_posts_h":6}' \
           '{"dias":["seg"],"horarios":["25:99"],"minimo_entre_posts_h":6}' \
           '{"dias":[],"horarios":["12:00"],"minimo_entre_posts_h":6}' \
           '{"dias":["seg"],"horarios":[],"minimo_entre_posts_h":6}' \
           '{"dias":["seg"],"horarios":["12:00"],"minimo_entre_posts_h":-1}' \
           '{"dias":["seg"],"horarios":["12:00"]}' \
           'não é json'; do
    _cad "$d/c.json" "$c"
    _ps "$d/c.json" 1 --now "$NOW" >/dev/null 2>&1 && _fail "cadência inválida aceita: $c"
  done
  _cad "$d/c.json" "$CAD"
  for c in 0 -1 abc 1.5 101; do
    _ps "$d/c.json" "$c" --now "$NOW" >/dev/null 2>&1 && _fail "quantidade inválida aceita: $c"
  done
  rm -rf "$d"
}

test_output_passes_schedule_validation() {
  local d out; d="$(mktemp -d)"; _cad "$d/c.json" "$CAD"; printf 'v' > "$d/v.mp4"
  out=$(_ps "$d/c.json" 4 --now "$NOW") || _fail "propose_slots falhou"
  python3 - "$d/plan.json" "$out" <<'PY'
import json, sys
horas = sys.argv[2].split("\n")
posts = [{"id": f"p{i}", "video": "v.mp4", "legenda": "x", "hashtags": [], "perfis": [{"rede": "instagram", "conta": "a"}], "data_hora": h}
         for i, h in enumerate(horas, 1)]
json.dump({"posts": posts}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$NOW" || _fail "horários propostos não passam na validação"
  rm -rf "$d"
}
