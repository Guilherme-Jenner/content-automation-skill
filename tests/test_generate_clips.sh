#!/usr/bin/env bash
# Testes de scripts/generate-clips.sh com o gerador falso (nunca usa crédito real)

_gc() { bash "$ROOT/scripts/generate-clips.sh" "$@"; }
_bg() { python3 "$ROOT/scripts/budget.py" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# _prep <dir> <teto> → gen-plan.json com c1 (4 s), c2 (5 s), c3 (6 s) em 480p sem áudio (fake: 4 + 5 + 6 = 15 créditos) e budget.json
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
_quote() { _gc "$1/g.json" "$1/w" --budget "$1/b.json" --stage quote --generator fake >/dev/null 2>&1 || _fail "quote falhou"; }
_total() { _bg status "$1/b.json" | sed -n 's/^total cotado: //p'; }
_flow() { _prep "$1" "$2"; _quote "$1"; _bg confirm "$1/b.json" "$(_total "$1")" >/dev/null 2>&1 || _fail "confirm falhou"; }
_run() { local d="$1"; shift; _gc "$d/g.json" "$d/w" --budget "$d/b.json" --stage run --generator fake "$@"; }
_count_clips() { find "$1/w/clips" -name '*.mp4' 2>/dev/null | wc -l | tr -d ' '; }

test_quote_generates_nothing_and_shows_the_total() {
  local d; d="$(mktemp -d)"; _prep "$d" 100; _quote "$d"
  assert_eq 15 "$(_total "$d")" "4 + 5 + 6"
  assert_eq 0 "$(_count_clips "$d")" "cotar não gera clipes"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  rm -rf "$d"
}

test_run_requires_confirmation() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100; _quote "$d"
  out=$(_run "$d" 2>&1) && _fail "run sem confirmação deveria falhar"
  assert_contains "$out" "confirm" "mensagem"
  assert_eq 0 "$(_count_clips "$d")" "nada gerado"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  rm -rf "$d"
}

test_happy_path_spends_the_total_and_writes_the_manifest() {
  local d; d="$(mktemp -d)"; _flow "$d" 100
  _run "$d" >/dev/null 2>&1 || _fail "run falhou"
  assert_eq 3 "$(_count_clips "$d")" "3 clipes"
  assert_near 5 "$(_dur "$d/w/clips/c2.mp4")" 0.2 "duração da cena 2"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 15" "gasto total"
  assert_eq 3 "$(json_get "$d/w/clips-manifest.json" "len(d['clips'])")" "3 entradas no manifesto"
  assert_eq True "$(json_get "$d/w/clips-manifest.json" "all(c['conteudo_ia'] for c in d['clips'].values())")" "marcado como conteúdo de IA"
  assert_eq fake "$(json_get "$d/w/clips-manifest.json" "d['clips']['c1']['origem']")" "origem"
  python3 - "$d/w" <<'PY' || _fail "sha256 do manifesto não bate com o arquivo"
import hashlib, json, os, sys
w = sys.argv[1]
m = json.load(open(os.path.join(w, "clips-manifest.json"), encoding="utf-8"))
for cid, c in m["clips"].items():
    h = hashlib.sha256(open(os.path.join(w, c["arquivo"]), "rb").read()).hexdigest()
    assert h == c["sha256"], cid
PY
  rm -rf "$d"
}

test_total_above_ceiling_blocks_the_confirmation() {
  local d out; d="$(mktemp -d)"; _prep "$d" 10; _quote "$d"
  out=$(_bg confirm "$d/b.json" 15 2>&1) && _fail "15 > 10 deveria ser recusado"
  assert_contains "$out" "excede" "mensagem"
  _run "$d" >/dev/null 2>&1 && _fail "run sem confirmação"
  assert_eq 0 "$(_count_clips "$d")" "nada gerado"
  rm -rf "$d"
}

test_overrun_is_registered_and_stops_the_batch() {
  local d out; d="$(mktemp -d)"; _flow "$d" 100
  out=$(CLO_GEN_FAKE_OVERRUN=c2 _run "$d" 2>&1) && _fail "estouro deveria dar erro"
  assert_file_exists "$d/w/clips/c1.mp4"; assert_file_exists "$d/w/clips/c2.mp4"
  [ ! -e "$d/w/clips/c3.mp4" ] || _fail "o lote deveria parar no estouro"
  assert_contains "$out" "Estouro" "relato"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 14" "4 + 10 (efetivo)"
  rm -rf "$d"
}

test_rerun_after_overrun_does_not_charge_twice() {
  local d out; d="$(mktemp -d)"; _flow "$d" 100
  CLO_GEN_FAKE_OVERRUN=c2 _run "$d" >/dev/null 2>&1
  out=$(_run "$d" 2>&1) || _fail "retomar deveria funcionar: $out"
  assert_contains "$out" "já concluída" "cenas pagas são puladas"
  assert_file_exists "$d/w/clips/c3.mp4"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 20" "14 + 6, sem cobrar c1 e c2 de novo"
  assert_eq 3 "$(json_get "$d/w/clips-manifest.json" "len(d['clips'])")" "manifesto completo"
  rm -rf "$d"
}

test_plan_edited_after_confirmation_is_refused() {
  local d out; d="$(mktemp -d)"; _flow "$d" 100
  python3 - "$d/g.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"][0]["prompt"] = "outro prompt, outra cena"
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_run "$d" 2>&1) && _fail "plano alterado depois da confirmação"
  assert_contains "$out" "sem cotação confirmada" "mensagem"
  assert_eq 0 "$(_count_clips "$d")" "nada gerado"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  rm -rf "$d"
}

test_existing_clip_needs_force_before_any_spend() {
  local d out; d="$(mktemp -d)"; _flow "$d" 100
  mkdir -p "$d/w/clips"; echo existente > "$d/w/clips/c1.mp4"
  out=$(_run "$d" 2>&1) && _fail "deveria recusar"
  assert_contains "$out" "--force" "mensagem"
  assert_eq existente "$(cat "$d/w/clips/c1.mp4")" "arquivo intacto"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto antes da recusa"
  rm -rf "$d"
}

test_concurrent_runs_never_charge_the_same_scene_twice() {
  local d i ok=0; d="$(mktemp -d)"; _flow "$d" 100
  for i in 1 2; do (_run "$d" >/dev/null 2>&1; echo $? > "$d/rc$i") & done
  wait
  for i in 1 2; do [ "$(cat "$d/rc$i")" = 0 ] && ok=$((ok + 1)); done
  [ "$ok" -ge 1 ] || _fail "ao menos uma execução deveria concluir"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 15" "cada cena cobrada uma vez"
  rm -rf "$d"
}

test_quote_again_skips_confirmed_scenes() {
  local d; d="$(mktemp -d)"; _flow "$d" 100
  _gc "$d/g.json" "$d/w" --budget "$d/b.json" --stage quote --generator fake >/dev/null 2>&1 || _fail "quote repetido não deveria morrer"
  rm -rf "$d"
}

test_relative_paths_and_spaces() {
  local d; d="$(mktemp -d)/pasta com espaço é"; _prep "$d" 100
  (cd "$d" && bash "$ROOT/scripts/generate-clips.sh" g.json "saída" --budget b.json --stage quote --generator fake >/dev/null 2>&1) || _fail "quote relativo falhou"
  _bg confirm "$d/b.json" "$(_total "$d")" >/dev/null 2>&1
  (cd "$d" && bash "$ROOT/scripts/generate-clips.sh" g.json "saída" --budget b.json --stage run --generator fake >/dev/null 2>&1) || _fail "run relativo falhou"
  assert_file_exists "$d/saída/clips/c1.mp4"
  rm -rf "$d"
}

test_invalid_plan_and_unknown_generator_refused() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100
  out=$(_gc "$d/g.json" "$d/w" --budget "$d/b.json" --stage quote --generator real 2>&1) && _fail "gerador desconhecido aceito"
  assert_contains "$out" "gerador" "mensagem"
  python3 - "$d/g.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"][0]["duracao_s"] = 2
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(_gc "$d/g.json" "$d/w" --budget "$d/b.json" --stage quote --generator fake 2>&1) && _fail "plano inválido aceito"
  assert_contains "$out" "duracao_s" "mensagem"
  rm -rf "$d"
}
