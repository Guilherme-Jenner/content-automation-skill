#!/usr/bin/env bash
# Regressões dos achados da revisão da Fase 3 (C1, I1–I6)

_gc() { bash "$ROOT/scripts/generate-clips.sh" "$@"; }
_bg() { python3 "$ROOT/scripts/budget.py" "$@"; }
_cm() { python3 "$ROOT/scripts/clips_manifest.py" "$@"; }
UUID1="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6b"
UUID2="9a8b7c6d-1234-4abc-8def-0123456789ab"

# _prep <dir> <teto> → c1 (4 s), c2 (5 s), c3 (6 s) em 480p sem áudio (fake: 4 + 5 + 6 = 15 créditos)
_prep() {
  mkdir -p "$1"
  python3 - "$1/g.json" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "pessoa olhando o celular", "duracao_s": 4},
                     {"id": "c2", "prompt": "tela do app organizando tarefas", "duracao_s": 5},
                     {"id": "c3", "prompt": "logo e chamada para ação", "duracao_s": 6}]},
          open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  _bg init "$1/b.json" "$2" >/dev/null
}
_fake() { local d="$1"; shift; _gc "$d/g.json" "$d/w" --budget "$d/b.json" --generator fake "$@"; }
_total() { _bg status "$1/b.json" | sed -n 's/^total cotado: //p'; }
_fake_flow() { _prep "$1" "$2"; _fake "$1" --stage quote >/dev/null 2>&1; _bg confirm "$1/b.json" "$(_total "$1")" >/dev/null 2>&1 || _fail "confirm falhou"; }
_ag() { local d="$1"; shift; _gc "$d/g.json" "$d/w" --generator mcp-agent --budget "$d/b.json" "$@"; }
_agent_flow() { # <dir> <teto> : cota e confirma as 3 cenas (4 + 5 + 6)
  _prep "$1" "$2"
  _ag "$1" --stage register-quote --scene c1 --custo 4 >/dev/null; _ag "$1" --stage register-quote --scene c2 --custo 5 >/dev/null
  _ag "$1" --stage register-quote --scene c3 --custo 6 >/dev/null
  _bg confirm "$1/b.json" 15 >/dev/null 2>&1 || _fail "confirm falhou"
}
_clip() { # <arquivo> <segundos> [tamanho]
  ffmpeg -v error -y -f lavfi -i "testsrc2=size=${3:-480x854}:rate=25:duration=$2" -c:v libx264 -pix_fmt yuv420p -an "$1" </dev/null
}
_reg() { local d="$1" cena="$2" job="$3" custo="$4" arq="$5"; shift 5
  _ag "$d" --stage register --scene "$cena" --job-id "$job" --custo "$custo" --arquivo "$arq" "$@"; }

# C1 ------------------------------------------------------------------------
test_after_an_overrun_nothing_more_is_generated_without_a_new_decision() {
  local d out; d="$(mktemp -d)"; _fake_flow "$d" 15
  CLO_GEN_FAKE_OVERRUN=c1 _fake "$d" --stage run >/dev/null 2>&1   # c1 custou 8 em vez de 4: comprometido 8+5+6 = 19 > 15
  out=$(_fake "$d" --stage run 2>&1) && _fail "rodar de novo depois do estouro não pode gastar sem nova decisão"
  assert_contains "$out" "teto" "mensagem cita o teto"
  [ ! -e "$d/w/clips/c2.mp4" ] || _fail "c2 não pode ter sido gerada"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 8" "o gasto não passou do que já estava registrado"
  rm -rf "$d"
}

test_raising_the_ceiling_is_the_explicit_way_out() {
  local d out; d="$(mktemp -d)"; _fake_flow "$d" 15
  CLO_GEN_FAKE_OVERRUN=c1 _fake "$d" --stage run >/dev/null 2>&1   # comprometido 8 + 5 + 6 = 19 > 15
  out=$(_bg raise "$d/b.json" 10 2>&1) && _fail "reduzir o teto não é aumentar"
  assert_contains "$out" "maior" "mensagem"
  _fake "$d" --stage run >/dev/null 2>&1 && _fail "ainda acima do teto"
  _bg raise "$d/b.json" 19 >/dev/null 2>&1 || _fail "aumentar o teto (decisão explícita do usuário) deveria funcionar"
  _fake "$d" --stage run >/dev/null 2>&1 || _fail "com o teto em 19 (8 + 5 + 6) deveria gerar o resto"
  assert_file_exists "$d/w/clips/c2.mp4"; assert_file_exists "$d/w/clips/c3.mp4"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 19" "8 + 5 + 6"
  rm -rf "$d"
}

test_drop_refuses_spent_items_and_raise_is_explicit() {
  local d item; d="$(mktemp -d)"; _fake_flow "$d" 100
  _fake "$d" --stage run >/dev/null 2>&1
  item=$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key c1)
  _bg drop "$d/b.json" "$item" >/dev/null 2>&1 && _fail "item já gasto não pode ser descartado"
  _bg drop "$d/b.json" nao-existe >/dev/null 2>&1 && _fail "item inexistente"
  _bg raise "$d/b.json" 200 >/dev/null 2>&1 || _fail "aumentar o teto deveria funcionar"
  assert_contains "$(_bg status "$d/b.json")" "teto: 200" "novo teto"
  item=$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key c1)
  _bg quote "$d/b.json" extra-1 3 >/dev/null
  _bg drop "$d/b.json" extra-1 >/dev/null 2>&1 || _fail "descartar item pendente não gasto deveria funcionar"
  assert_eq 0 "$(_bg status "$d/b.json" | grep -c extra-1)" "o item descartado some do orçamento"
  rm -rf "$d"
}

test_agent_payload_is_refused_when_commitments_exceed_the_ceiling() {
  local d out; d="$(mktemp -d)"; _agent_flow "$d" 15
  _ag "$d" --stage payload --scene c1 >/dev/null || _fail "payload de c1 deveria sair"
  _clip "$d/x.mp4" 4
  _reg "$d" c1 "$UUID1" 12 "$d/x.mp4" >/dev/null 2>&1   # estouro: 12 em vez de 4 → comprometido 12+5+6 = 23 > 15
  out=$(_ag "$d" --stage payload --scene c2 2>&1) && _fail "payload da próxima cena não pode sair depois do estouro"
  assert_contains "$out" "teto" "mensagem cita o teto"
  rm -rf "$d"
}

# I1 ------------------------------------------------------------------------
test_generation_payload_is_emitted_once_and_register_needs_it() {
  local d out; d="$(mktemp -d)"; _agent_flow "$d" 100; _clip "$d/x.mp4" 4
  out=$(_reg "$d" c1 "$UUID1" 4 "$d/x.mp4" 2>&1) && _fail "register sem payload emitido"
  assert_contains "$out" "payload" "mensagem"
  _ag "$d" --stage payload --scene c1 >/dev/null || _fail "primeiro payload deveria sair"
  out=$(_ag "$d" --stage payload --scene c1 2>&1) && _fail "segundo payload de geração não pode sair"
  assert_contains "$out" "já foi emitido" "mensagem"
  assert_contains "$out" "job" "orienta conferir o job"
  _ag "$d" --stage payload --scene c1 --reemitir >/dev/null 2>&1 || _fail "--reemitir (depois de conferir) deveria permitir"
  _ag "$d" --stage payload --scene c1 --cost-only >/dev/null || _fail "o payload de cotação não é limitado"
  rm -rf "$d"
}

# I2 ------------------------------------------------------------------------
test_concurrent_registers_of_the_same_scene_have_a_single_winner() {
  local d i ok=0; d="$(mktemp -d)"; _agent_flow "$d" 100
  _ag "$d" --stage payload --scene c1 >/dev/null
  _clip "$d/a.mp4" 4; _clip "$d/b.mp4" 5   # 5 s também passa (±1 s)
  (_reg "$d" c1 "$UUID1" 4 "$d/a.mp4" >/dev/null 2>&1; echo $? > "$d/rc1") &
  (_reg "$d" c1 "$UUID2" 4 "$d/b.mp4" >/dev/null 2>&1; echo $? > "$d/rc2") &
  wait
  for i in 1 2; do [ "$(cat "$d/rc$i")" = 0 ] && ok=$((ok + 1)); done
  assert_eq 1 "$ok" "exatamente um register deve vencer"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 4" "cobrado uma vez"
  python3 - "$d/w" <<'PY' || _fail "o manifesto não corresponde ao arquivo final"
import hashlib, json, os, sys
w = sys.argv[1]
c = json.load(open(os.path.join(w, "clips-manifest.json"), encoding="utf-8"))["clips"]["c1"]
assert hashlib.sha256(open(os.path.join(w, c["arquivo"]), "rb").read()).hexdigest() == c["sha256"]
PY
  rm -rf "$d"
}

# I3 ------------------------------------------------------------------------
test_register_rejects_files_that_are_not_the_scene() {
  local d out; d="$(mktemp -d)"; _agent_flow "$d" 100; _ag "$d" --stage payload --scene c1 >/dev/null
  _clip "$d/longo.mp4" 20
  out=$(_reg "$d" c1 "$UUID1" 4 "$d/longo.mp4" 2>&1) && _fail "clipe de 20 s numa cena de 4 s aceito"
  assert_contains "$out" "duração" "mensagem"
  _clip "$d/horizontal.mp4" 4 854x480
  out=$(_reg "$d" c1 "$UUID1" 4 "$d/horizontal.mp4" 2>&1) && _fail "clipe horizontal aceito"
  assert_contains "$out" "proporção" "mensagem"
  _clip "$d/ok.mp4" 4
  out=$(_reg "$d" c1 "$UUID1" 0 "$d/ok.mp4" 2>&1) && _fail "custo zero aceito"
  assert_contains "$out" "custo" "mensagem"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto nas recusas"
  rm -rf "$d"
}

test_register_rejects_reused_job_ids_and_reused_files() {
  local d out; d="$(mktemp -d)"; _agent_flow "$d" 100
  _ag "$d" --stage payload --scene c1 >/dev/null; _ag "$d" --stage payload --scene c2 >/dev/null
  _clip "$d/a.mp4" 4; _clip "$d/b.mp4" 5
  _reg "$d" c1 "$UUID1" 4 "$d/a.mp4" >/dev/null 2>&1 || _fail "primeiro registro falhou"
  out=$(_reg "$d" c2 "$UUID1" 5 "$d/b.mp4" 2>&1) && _fail "mesmo job-id em duas cenas aceito"
  assert_contains "$out" "job" "mensagem"
  cp "$d/a.mp4" "$d/a-copia.mp4"
  out=$(_reg "$d" c2 "$UUID2" 5 "$d/a-copia.mp4" 2>&1) && _fail "mesmo arquivo em duas cenas aceito"
  assert_contains "$out" "outra cena" "mensagem"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 4" "só a primeira foi cobrada"
  rm -rf "$d"
}

# I6 ------------------------------------------------------------------------
test_verify_rejects_a_clip_made_for_an_older_version_of_the_plan() {
  local d out; d="$(mktemp -d)"; _fake_flow "$d" 100; _fake "$d" --stage run >/dev/null 2>&1 || _fail "run falhou"
  _cm verify "$d/w/clips-manifest.json" "$d/g.json" >/dev/null 2>&1 || _fail "verify deveria passar com o plano original"
  python3 - "$d/g.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"][1]["prompt"] = "outro prompt, outra cena"
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_cm verify "$d/w/clips-manifest.json" "$d/g.json" 2>&1) && _fail "clipe de versão antiga do plano aceito"
  assert_contains "$out" "c2" "cita a cena"
  assert_contains "$out" "plano" "mensagem"
  rm -rf "$d"
}
