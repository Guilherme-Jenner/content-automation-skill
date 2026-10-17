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

test_real_katana_is_not_implemented_yet() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 1
  msg=$(_rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "ainda não implementado" "mensagem"
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
  _bg confirm "$d/b.json" >/dev/null 2>&1 || _fail "confirm falhou"
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
  msg=$(_bg confirm "$d/b.json" 2>&1) && _fail "10,5 > 10 deveria ser recusado"
  assert_contains "$msg" "excede" "mensagem"
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" >/dev/null 2>&1 && _fail "run sem confirmação"
  [ -z "$(find "$d/w" -name 'final-*')" ] || _fail "nada pode ser gerado acima do teto"
  rm -rf "$d"
}

test_overrun_blocks_that_variant_and_keeps_previous() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 3
  _bg init "$d/b.json" 100 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1
  _bg confirm "$d/b.json" >/dev/null 2>&1
  out=$(CLO_KATANA=fake CLO_KATANA_FAKE_OVERRUN=2 _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) \
    && _fail "estouro da cotação deveria dar erro"
  assert_file_exists "$d/w/final-1.mp4"; assert_file_exists "$d/w/final-3.mp4"
  [ ! -e "$d/w/final-2.mp4" ] || _fail "variante que estourou não deveria ter saída"
  assert_contains "$out" "Falharam: 2" "relato"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 6" "só 1 e 3 foram gastas (3 + 3)"
  rm -rf "$d"
}

test_existing_output_needs_force_before_any_spend() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _prep "$d" "$f/tone_silence_tone.mp4" katana 2
  _bg init "$d/b.json" 100 >/dev/null
  CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage quote --budget "$d/b.json" >/dev/null 2>&1
  _bg confirm "$d/b.json" >/dev/null 2>&1
  echo existente > "$d/w/final-1.mp4"
  msg=$(CLO_KATANA=fake _rv "$f/tone_silence_tone.mp4" "$d/w" --variants "$d/p.json" --stage run --budget "$d/b.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "--force" "mensagem"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto antes da recusa"
  rm -rf "$d"
}
