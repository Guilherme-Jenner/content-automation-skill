#!/usr/bin/env bash
# Testes de scripts/schedule.sh (simulação, confirmação com aprovação, idempotência, agendador falso)

NOW="2026-10-20T10:00:00-03:00"

_sch() { bash "$ROOT/scripts/schedule.sh" "$@"; }

# _setup <dir> → plan.json com o post p1 (vídeo v.mp4), aprovado em $dir/ap
_setup() {
  mkdir -p "$1"; printf 'video de teste' > "$1/v.mp4"
  python3 - "$1/plan.json" <<'PY'
import json, sys
json.dump({"posts": [{"id": "p1", "video": "v.mp4", "legenda": "Rotina organizada ✨", "hashtags": ["#clo"],
                      "perfis": [{"rede": "instagram", "conta": "clo.app"}, {"rede": "tiktok", "conta": "clo.app"}],
                      "data_hora": "2026-10-21T12:00:00-03:00"}]}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
_approve() { python3 "$ROOT/scripts/approval.py" approve "$1/plan.json" p1 "$1/ap" --now "$NOW" >/dev/null 2>&1 || _fail "approve falhou"; }
_run() { # <dir> [extra...]
  local d="$1"; shift
  _sch "$d/plan.json" p1 --approvals "$d/ap" --log "$d/log.json" --scheduler fake --now "$NOW" "$@"
}
_count() { python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
    print(sum(1 for v in d['agendamentos'].values() if v['estado'] == 'agendado'))
except FileNotFoundError:
    print(0)" "$1"; }

test_dry_run_writes_nothing() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  out=$(_run "$d" 2>&1) || _fail "simulação falhou: $out"
  assert_contains "$out" "SIMULAÇÃO" "avisa que é simulação"
  assert_contains "$out" "--confirm" "diz como agendar de verdade"
  [ ! -e "$d/log.json" ] || _fail "simulação não pode gravar o log"
  rm -rf "$d"
}

test_confirm_requires_valid_approval() {
  local d out; d="$(mktemp -d)"; _setup "$d"
  out=$(_run "$d" --confirm 2>&1) && _fail "agendou sem aprovação"
  assert_contains "$out" "aprovação" "mensagem"
  [ ! -e "$d/log.json" ] || _fail "não deveria gravar nada"
  out=$(_run "$d" 2>&1) && _fail "nem a simulação deve passar sem aprovação"
  rm -rf "$d"
}

test_confirm_schedules_once_and_logs() {
  local d; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  _run "$d" --confirm >/dev/null 2>&1 || _fail "agendamento falhou"
  assert_eq 1 "$(_count "$d/log.json")" "uma entrada agendada"
  assert_contains "$(cat "$d/log.json")" "fake-" "id externo do agendador falso"
  assert_contains "$(cat "$d/log.json")" "tiktok" "perfis registrados"
  rm -rf "$d"
}

test_second_schedule_refused() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  _run "$d" --confirm >/dev/null 2>&1
  out=$(_run "$d" --confirm 2>&1) && _fail "segundo agendamento aceito"
  assert_contains "$out" "já agendado" "mensagem"
  assert_eq 1 "$(_count "$d/log.json")" "continua uma entrada"
  out=$(_run "$d" 2>&1) && _fail "a simulação também deve avisar"
  assert_contains "$out" "já agendado" "simulação avisa"
  rm -rf "$d"
}

test_concurrent_schedules_only_one_wins() {
  local d i ok=0; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  for i in 1 2 3 4 5 6; do (_run "$d" --confirm >/dev/null 2>&1; echo $? > "$d/rc$i") & done
  wait
  for i in 1 2 3 4 5 6; do [ "$(cat "$d/rc$i")" = 0 ] && ok=$((ok + 1)); done
  assert_eq 1 "$ok" "exatamente um agendamento deve dar certo"
  assert_eq 1 "$(_count "$d/log.json")" "uma única entrada no log"
  rm -rf "$d"
}

test_expired_deadline_between_approval_and_schedule_rejected() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  out=$(_sch "$d/plan.json" p1 --approvals "$d/ap" --log "$d/log.json" --scheduler fake --now "2026-10-21T11:50:00-03:00" --confirm 2>&1) \
    && _fail "horário já próximo/passado aceito"
  assert_contains "$out" "data_hora" "mensagem"
  [ ! -e "$d/log.json" ] || _fail "não deveria gravar nada"
  rm -rf "$d"
}

test_unknown_scheduler_not_implemented() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  out=$(_sch "$d/plan.json" p1 --approvals "$d/ap" --log "$d/log.json" --scheduler metricool --now "$NOW" --confirm 2>&1) \
    && _fail "agendador real não existe ainda"
  assert_contains "$out" "ainda não implementado" "mensagem"
  [ ! -e "$d/log.json" ] || _fail "não deveria gravar nada"
  out=$(_sch "$d/plan.json" p1 --approvals "$d/ap" --log "$d/log.json" --now "$NOW" 2>&1) && _fail "--scheduler é obrigatório"
  assert_contains "$out" "--scheduler" "mensagem"
  rm -rf "$d"
}

test_changed_content_after_approval_rejected() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  printf 'outro video' > "$d/v.mp4"
  out=$(_run "$d" --confirm 2>&1) && _fail "vídeo alterado aceito"
  assert_contains "$out" "vídeo" "mensagem"
  assert_eq 0 "$(_count "$d/log.json")" "nada agendado"
  rm -rf "$d"
}

test_scheduler_failure_releases_the_reservation() {
  local d; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  CLO_FAKE_SCHEDULER_FAIL=1 _run "$d" --confirm >/dev/null 2>&1 && _fail "falha do agendador deveria dar erro"
  assert_eq 0 "$(_count "$d/log.json")" "nada fica como agendado"
  _run "$d" --confirm >/dev/null 2>&1 || _fail "depois de uma falha, tentar de novo deve funcionar"
  assert_eq 1 "$(_count "$d/log.json")" "agora sim"
  rm -rf "$d"
}

test_relative_paths_work() {
  local d; d="$(mktemp -d)"; _setup "$d"; _approve "$d"
  (cd "$d" && bash "$ROOT/scripts/schedule.sh" plan.json p1 --approvals ap --log log.json --scheduler fake --now "$NOW" --confirm >/dev/null 2>&1) \
    || _fail "caminhos relativos falharam"
  assert_eq 1 "$(_count "$d/log.json")" "agendado"
  rm -rf "$d"
}
