#!/usr/bin/env bash
# Porta de editor (scripts/run-variants.sh): local (custo zero) e Katana falso (com teto de gastos)

_rv() { CLO_TRANSCRIBER=fake bash "$ROOT/scripts/run-variants.sh" "$@"; }
_bg() { python3 "$ROOT/scripts/budget.py" "$@"; }

# _prep <dir> <video> <editor> <n variantes 1..3>  → propose + variants-plan.json (3 variantes aprovadas, até n)
_prep() {
  mkdir -p "$1"
  CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$2" "$1/w" --stage propose >/dev/null 2>&1 || _fail "propose falhou"
  python3 - "$1/p.json" "$2" "$3" "$4" <<'PY'
import json, sys
def v(i, trechos, g, estilo="padrao"):
    return {"id": i, "tipo": "trecho_diferente", "trechos": [{"inicio_s": a, "fim_s": b} for a, b in trechos], "gancho": g,
            "ritmo": {"min_silencio_s": 0.6, "margem_s": 0.15}, "legenda_estilo": estilo, "aprovada": True, "achados": ["x"]}
todas = [v("1", [(0, 2)], "A"), v("2", [(3.5, 6.5)], "B"), v("3", [(0, 2)], "C", "destaque")]
n = int(sys.argv[4])
json.dump({"bruto": sys.argv[2], "editor": sys.argv[3], "quantidade": n, "duracao_s": 6.5, "variantes": todas[:n]},
          open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_local_editor_never_touches_the_budget() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" local 1
  _bg init "$d/b.json" 100 >/dev/null
  _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" >/dev/null 2>&1 || _fail "editor local falhou"
  assert_file_exists "$d/w/final-1.mp4"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  assert_eq 0 "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['itens']))" "$d/b.json")" "nenhum item no orçamento"
  rm -rf "$d"
}

test_real_katana_runs_through_the_agent_skill_not_a_script() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 1
  msg=$(_rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "edit-katana" "aponta a skill que conduz o Katana real"
  rm -rf "$d"
}

test_katana_fake_requires_a_budget() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 1
  msg=$(CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote 2>&1) && _fail "deveria exigir teto"
  assert_contains "$msg" "teto" "mensagem"
  rm -rf "$d"
}

test_katana_fake_quote_shows_total_and_generates_nothing() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 3
  _bg init "$d/b.json" 100 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1 || _fail "quote falhou"
  assert_contains "$(_bg status "$d/b.json")" "total cotado: 10.5" "2s*1,5 + 3s*1,5 + 2s*1,5"
  [ -z "$(find "$d/w" -name 'final-*')" ] || _fail "cotar não pode gerar nada"
  rm -rf "$d"
}

test_katana_fake_run_requires_confirmation() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 2
  _bg init "$d/b.json" 100 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1
  msg=$(CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) && _fail "run sem confirmação deveria falhar"
  assert_contains "$msg" "confirm" "mensagem"
  [ -z "$(find "$d/w" -name 'final-*')" ] || _fail "nada pode ser gerado sem confirmação"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  rm -rf "$d"
}

test_katana_fake_spends_and_produces_after_confirmation() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 3
  _bg init "$d/b.json" 100 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1
  _bg confirm "$d/b.json" 10.5 >/dev/null 2>&1 || _fail "confirm falhou"
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" >/dev/null 2>&1 || _fail "run falhou"
  local i
  for i in 1 2 3; do assert_file_exists "$d/w/final-$i.mp4"; done
  assert_contains "$(_bg status "$d/b.json")" "gasto: 10.5" "gasto total"
  rm -rf "$d"
}

test_total_above_ceiling_blocks_everything() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 3
  _bg init "$d/b.json" 10 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1
  msg=$(_bg confirm "$d/b.json" 10.5 2>&1) && _fail "10,5 > 10 deveria ser recusado"
  assert_contains "$msg" "excede" "mensagem"
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" >/dev/null 2>&1 && _fail "run sem confirmação"
  [ -z "$(find "$d/w" -name 'final-*')" ] || _fail "nada pode ser gerado acima do teto"
  rm -rf "$d"
}

# _flow <dir> <video> <n> <teto>  → propose + plano katana + init + quote + confirm do total (em $d/total)
_flow() {
  _prep "$1" "$2" katana "$3"
  _bg init "$1/b.json" "$4" >/dev/null
  CLO_KATANA=fake _rv "$2" "$1/w" --variants "$1/p.json" --stage quote --budget "$1/b.json" >/dev/null 2>&1 || _fail "quote falhou"
  _bg confirm "$1/b.json" "$(_bg status "$1/b.json" | sed -n 's/^total cotado: //p')" >/dev/null 2>&1 || _fail "confirm falhou"
}

test_overrun_is_registered_and_stops_the_batch() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _flow "$d" "$f/tone_silence_tone.mp4" 3 100
  out=$(CLO_KATANA=fake CLO_KATANA_FAKE_OVERRUN=2 _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) \
    && _fail "estouro da cotação deveria dar erro"
  assert_file_exists "$d/w/final-1.mp4"
  assert_file_exists "$d/w/final-2.mp4"
  [ ! -e "$d/w/final-3.mp4" ] || _fail "o lote deveria parar no estouro: a variante 3 não pode ser gerada"
  assert_contains "$out" "Estouro" "relato do estouro"
  assert_contains "$out" "interrompido" "relato de que o lote parou"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 12" "gasto efetivo registrado (3 + 9)"
  rm -rf "$d"
}

test_rerun_after_overrun_does_not_charge_twice_and_finishes_the_rest() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _flow "$d" "$f/tone_silence_tone.mp4" 3 100
  CLO_KATANA=fake CLO_KATANA_FAKE_OVERRUN=2 _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" >/dev/null 2>&1
  out=$(CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) \
    || _fail "retomar o lote deveria funcionar: $out"
  assert_contains "$out" "já concluída" "variantes pagas são puladas"
  assert_file_exists "$d/w/final-3.mp4"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 15" "12 + 3, sem cobrar 1 e 2 de novo"
  rm -rf "$d"
}

test_quote_again_skips_items_already_confirmed() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _flow "$d" "$f/tone_silence_tone.mp4" 2 100
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1 \
    || _fail "quote repetido não deveria morrer"
  rm -rf "$d"
}

test_confirmation_does_not_transfer_to_another_source_video() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _flow "$d" "$f/tone_silence_tone.mp4" 1 100
  cp "$f/tone_silence_tone.mp4" "$d/outro-bruto.mp4"
  python3 - "$d/p.json" "$d/q.json" "$d/outro-bruto.mp4" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["bruto"] = sys.argv[3]
json.dump(p, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  msg=$(CLO_KATANA=fake _rv "$d/outro-bruto.mp4" "$d/w2" --variants "$d/q.json" --stage run --budget "$d/b.json" 2>&1) \
    && _fail "a confirmação do outro bruto não pode valer aqui"
  assert_contains "$msg" "sem cotação confirmada" "mensagem"
  [ ! -e "$d/w2/final-1.mp4" ] || _fail "nada pode ser gerado"
  rm -rf "$d"
}

test_plan_edited_after_confirmation_is_refused() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _flow "$d" "$f/tone_silence_tone.mp4" 1 100
  python3 - "$d/p.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["variantes"][0]["trechos"] = [{"inicio_s": 0, "fim_s": 6}]
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  msg=$(CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) \
    && _fail "plano alterado depois da confirmação deveria ser recusado"
  assert_contains "$msg" "sem cotação confirmada" "mensagem"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  rm -rf "$d"
}

test_scripts_are_executable_in_git() {
  local f bad=""
  for f in $(git -C "$ROOT" ls-files 'scripts/*.sh' 'scripts/editors/*.sh'); do
    case "$(git -C "$ROOT" ls-files -s "$f")" in 100755*) ;; *) bad="$bad $f" ;; esac
  done
  [ -z "$bad" ] || _fail "sem bit de execução no git (quebra no Mac):$bad"
}

test_existing_output_needs_force_before_any_spend() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 2
  _bg init "$d/b.json" 100 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1
  _bg confirm "$d/b.json" 7.5 >/dev/null 2>&1
  echo existente > "$d/w/final-1.mp4"
  msg=$(CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "--force" "mensagem"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto antes da recusa"
  rm -rf "$d"
}
