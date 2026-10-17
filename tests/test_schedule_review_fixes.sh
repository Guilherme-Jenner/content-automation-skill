#!/usr/bin/env bash
# Regressões dos achados da revisão da Fase 2 (I1–I6)

NOW="2026-10-20T10:00:00-03:00"

_sch() { bash "$ROOT/scripts/schedule.sh" "$@"; }
_sl() { python3 "$ROOT/scripts/schedule_log.py" "$@"; }
_ap() { python3 "$ROOT/scripts/approval.py" "$@"; }

# _setup <dir> [instruções python]  → plan.json com p1 e p2 (vídeos v1.mp4 e v2.mp4)
_setup() {
  mkdir -p "$1"; printf 'video 1' > "$1/v1.mp4"; printf 'video 2' > "$1/v2.mp4"
  python3 - "$1/plan.json" "${2:-pass}" <<'PY'
import json, sys
def post(i, v, hora):
    return {"id": i, "video": v, "legenda": "Rotina organizada ✨", "hashtags": ["#clo"],
            "perfis": [{"rede": "instagram", "conta": "clo.app"}], "data_hora": hora}
p = {"posts": [post("p1", "v1.mp4", "2026-10-21T12:00:00-03:00"), post("p2", "v2.mp4", "2026-10-22T12:00:00-03:00")]}
exec(sys.argv[2])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}
_approve() { _ap approve "$1/plan.json" "$2" "$1/ap" --now "$NOW" --force >/dev/null 2>&1 || _fail "approve $2 falhou"; }
_run() { local d="$1" p="$2"; shift 2; _sch "$d/plan.json" "$p" --approvals "$d/ap" --scheduler fake --now "$NOW" "$@"; }
_count() { python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
    print(sum(1 for v in d['agendamentos'].values() if v['estado'] == 'agendado'))
except FileNotFoundError:
    print(0)" "$1"; }

# I1 ------------------------------------------------------------------------
test_changed_post_cannot_be_scheduled_twice_without_supersede() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d" p2
  _run "$d" p2 --confirm >/dev/null 2>&1 || _fail "primeiro agendamento falhou"
  _setup "$d" "p['posts'][1]['data_hora']='2026-10-22T19:00:00-03:00'"; _approve "$d" p2   # horário mudou e foi reaprovado
  out=$(_run "$d" p2 --confirm 2>&1) && _fail "reagendou sem cancelar o anterior"
  assert_contains "$out" "substit" "mensagem explica como reagendar"
  assert_eq 1 "$(_count "$d/.schedule-log.json")" "continua um único agendamento"
  _sl supersede "$d/.schedule-log.json" p2 >/dev/null 2>&1 || _fail "supersede falhou"
  _run "$d" p2 --confirm >/dev/null 2>&1 || _fail "depois de substituir, o novo horário deve ser agendável"
  assert_contains "$(cat "$d/.schedule-log.json")" "substituido" "o anterior fica registrado"
  assert_eq 1 "$(_count "$d/.schedule-log.json")" "só o novo está agendado"
  rm -rf "$d"
}

# I2 ------------------------------------------------------------------------
test_log_location_is_fixed_next_to_the_plan() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d" p1
  out=$(_run "$d" p1 --confirm --log "$d/outro.json" 2>&1) && _fail "--log livre não pode existir"
  assert_contains "$out" "--log" "mensagem"
  _run "$d" p1 --confirm >/dev/null 2>&1 || _fail "agendamento falhou"
  assert_file_exists "$d/.schedule-log.json"
  rm -rf "$d"
}

# I3 ------------------------------------------------------------------------
test_reserve_requires_approval_and_adapter_requires_a_verified_snapshot() {
  local d out snap; d="$(mktemp -d)"; _setup "$d"
  out=$(_sl reserve "$d/plan.json" p1 "$d/.schedule-log.json" fake "$d/ap" 2>&1) && _fail "reserve sem aprovação aceito"
  assert_contains "$out" "aprovação" "mensagem"
  [ ! -e "$d/.schedule-log.json" ] || _fail "não deveria gravar nada"
  out=$(bash "$ROOT/scripts/schedulers/fake.sh" "$d" 2>&1) && _fail "o agendador aceitou uma pasta que não é um snapshot aprovado"
  assert_contains "$out" "snapshot" "mensagem"
  _approve "$d" p1
  snap=$(_sl reserve "$d/plan.json" p1 "$d/.schedule-log.json" fake "$d/ap" | tail -1) || _fail "reserve com aprovação falhou"
  bash "$ROOT/scripts/schedulers/fake.sh" "$snap" >/dev/null 2>&1 || _fail "snapshot aprovado deveria ser aceito"
  printf 'adulterado' > "$snap"/video.*
  bash "$ROOT/scripts/schedulers/fake.sh" "$snap" >/dev/null 2>&1 && _fail "snapshot adulterado aceito"
  rm -rf "$d"
}

test_content_changed_right_before_reserve_is_not_scheduled() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d" p1
  printf 'trocado depois da aprovação' > "$d/v1.mp4"
  out=$(_sl reserve "$d/plan.json" p1 "$d/.schedule-log.json" fake "$d/ap" 2>&1) && _fail "reserve aceitou vídeo alterado"
  assert_contains "$out" "vídeo" "mensagem"
  rm -rf "$d"
}

# I4 ------------------------------------------------------------------------
test_release_needs_proof_for_a_fresh_reservation() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d" p1
  _sl reserve "$d/plan.json" p1 "$d/.schedule-log.json" fake "$d/ap" >/dev/null 2>&1 || _fail "reserve falhou"
  out=$(_sl release "$d/plan.json" p1 "$d/.schedule-log.json" 2>&1) && _fail "liberou reserva recente sem conferência"
  assert_contains "$out" "conferir" "orienta conferir no agendador"
  _sl release "$d/plan.json" p1 "$d/.schedule-log.json" --conferido >/dev/null 2>&1 || _fail "--conferido deveria liberar"
  # reserva antiga (processo que caiu há horas) pode ser liberada sem a flag
  _sl reserve "$d/plan.json" p1 "$d/.schedule-log.json" fake "$d/ap" >/dev/null 2>&1
  python3 - "$d/.schedule-log.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for v in d["agendamentos"].values():
    v["atualizado_em"] = "2020-01-01T00:00:00+00:00"
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"))
PY
  _sl release "$d/plan.json" p1 "$d/.schedule-log.json" >/dev/null 2>&1 || _fail "reserva antiga deveria poder ser liberada"
  rm -rf "$d"
}

test_orphan_reservation_is_explained_to_the_user() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d" p1
  _sl reserve "$d/plan.json" p1 "$d/.schedule-log.json" fake "$d/ap" >/dev/null 2>&1
  out=$(_run "$d" p1 2>&1) && _fail "post com reserva em andamento não pode seguir"
  assert_contains "$out" "em_andamento" "estado"
  assert_contains "$out" "conferir" "orientação para conferir no agendador antes de liberar"
  rm -rf "$d"
}

# I5 ------------------------------------------------------------------------
test_overdue_post_does_not_block_the_others() {
  local d out; d="$(mktemp -d)"; _setup "$d" "p['posts'][0]['data_hora']='2026-10-19T12:00:00-03:00'"
  out=$(_ap approve "$d/plan.json" p1 "$d/ap" --now "$NOW" 2>&1) && _fail "post vencido aprovado"
  assert_contains "$out" "data_hora" "o vencido continua recusado"
  _approve "$d" p2
  _run "$d" p2 --confirm >/dev/null 2>&1 || _fail "p2 válido não pode ser bloqueado pelo p1 vencido"
  bash "$ROOT/scripts/export_package.sh" "$d/plan.json" p2 "$d/out" --now "$NOW" >/dev/null 2>&1 || _fail "export de p2 bloqueado pelo p1 vencido"
  rm -rf "$d"
}

test_structural_errors_still_block_everything() {
  local d; d="$(mktemp -d)"; _setup "$d" "p['posts'][0]['id']='P2'"   # ids que diferem só por caixa
  _ap approve "$d/plan.json" p2 "$d/ap" --now "$NOW" >/dev/null 2>&1 && _fail "ids duplicados deveriam bloquear o plano inteiro"
  rm -rf "$d"
}

# I6 ------------------------------------------------------------------------
test_now_flag_is_refused_outside_tests() {
  local d out; d="$(mktemp -d)"; _setup "$d"; _approve "$d" p1
  out=$(env -u CLO_ALLOW_TEST_NOW bash "$ROOT/scripts/schedule.sh" "$d/plan.json" p1 --approvals "$d/ap" --scheduler fake --now "2020-01-01T00:00:00-03:00" --confirm 2>&1) \
    && _fail "--now aceito fora dos testes"
  assert_contains "$out" "só para testes" "mensagem"
  env -u CLO_ALLOW_TEST_NOW python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "2020-01-01T00:00:00-03:00" >/dev/null 2>&1 \
    && _fail "validate_schedule aceitou --now fora dos testes"
  env -u CLO_ALLOW_TEST_NOW python3 "$ROOT/scripts/propose_slots.py" "$d/c.json" 1 --now "2020-01-01T00:00:00-03:00" >/dev/null 2>&1 \
    && _fail "propose_slots aceitou --now fora dos testes"
  [ ! -e "$d/.schedule-log.json" ] || _fail "não deveria gravar nada"
  rm -rf "$d"
}
