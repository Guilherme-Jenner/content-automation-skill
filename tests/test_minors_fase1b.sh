#!/usr/bin/env bash
# Minors adiados das fases 1b/3 (ledger): validador de variantes, variant_info, usage, estado velho após falha, cotação zero

_VP="$ROOT/tests/data/variants_valid.json"

test_short_variant_error_is_not_hidden_by_an_earlier_error() {
  local d out; d="$(mktemp -d)"
  python3 - "$_VP" "$d/v.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["variantes"][0]["achados"] = []                                # erro na primeira variante
d["variantes"][1]["trechos"] = [{"inicio_s": 0, "fim_s": 0.5}]    # < 1 s na segunda
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(python3 "$ROOT/scripts/validate_variants.py" "$d/v.json" 2>&1) && _fail "plano inválido aceito"
  assert_contains "$out" "achados" "erro da primeira variante"
  assert_contains "$out" "menos de 1 s" "erro da segunda variante aparece junto"
  rm -rf "$d"
}

test_variant_info_unknown_id_is_a_clear_error() {
  local out
  out=$(python3 "$ROOT/scripts/variant_info.py" "$_VP" get nao-existe 2>&1) && _fail "id inexistente aceito"
  assert_contains "$out" "nao-existe" "cita o id"
  case "$out" in *Traceback*) _fail "traceback exposto ao usuário";; esac
}

test_subtitles_usage_mentions_style() {
  local out; out=$(bash "$ROOT/scripts/subtitles.sh" 2>&1) && _fail "sem argumentos deveria falhar"
  assert_contains "$out" "--style" "uso cita --style"
}

test_edit_recorded_skill_schema_path_uses_plugin_root() {
  local s; s=$(cat "$ROOT/skills/edit-recorded/SKILL.md")
  assert_contains "$s" 'CLAUDE_PLUGIN_ROOT}/schemas/variants-plan.schema.json' "caminho do schema via raiz do plugin"
}

test_zero_quote_is_refused() {
  local d out; d="$(mktemp -d)"
  python3 "$ROOT/scripts/budget.py" init "$d/b.json" 100 >/dev/null
  out=$(python3 "$ROOT/scripts/budget.py" quote "$d/b.json" clip-x 0 2>&1) && _fail "cotação 0 aceita"
  assert_contains "$out" "maior que zero" "mensagem"
  rm -rf "$d"
}

_er() { CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$@"; }
_vsetup() { # dir video [duracao_s do plano]
  mkdir -p "$1"
  _er "$2" "$1/w" --stage propose >/dev/null 2>&1 || _fail "propose falhou"
  python3 - "$1/variants-plan.json" "$2" "${3:-6.5}" <<'PY'
import json, sys
def v(i, trechos, gancho):
    return {"id": i, "tipo": "trecho_diferente", "trechos": [{"inicio_s": a, "fim_s": b} for a, b in trechos], "gancho": gancho,
            "ritmo": {"min_silencio_s": 0.6, "margem_s": 0.15}, "legenda_estilo": "padrao", "aprovada": True, "achados": ["Hook nos 3 primeiros segundos"]}
json.dump({"bruto": sys.argv[2], "editor": "local", "quantidade": 2, "duracao_s": float(sys.argv[3]),
           "variantes": [v("1", [(0, 2)], "Gancho A"), v("2", [(3.5, 6.5)], "Gancho B")]}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_forced_rerun_that_fails_does_not_leave_the_old_output() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _vsetup "$d" "$f/tone_silence_tone.mp4"
  _er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" >/dev/null 2>&1 || _fail "primeira execução falhou"
  CLO_TEST_FAIL_VARIANT=2 _er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" --force >/dev/null 2>&1 && _fail "deveria falhar"
  assert_file_exists "$d/w/final-1.mp4"
  [ ! -e "$d/w/final-2.mp4" ] || _fail "o final-2.mp4 antigo ficou, embora o relato diga que a variante 2 falhou"
  [ ! -e "$d/w/final-2.srt" ] || _fail "o final-2.srt antigo ficou"
  rm -rf "$d"
}

test_plan_duration_is_checked_against_the_video_before_the_batch() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _vsetup "$d" "$f/tone_silence_tone.mp4" 30
  out=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" 2>&1) && _fail "duração incompatível aceita"
  assert_contains "$out" "duração" "mensagem"
  [ ! -d "$d/w/v1" ] || _fail "começou a processar antes de conferir a duração"
  rm -rf "$d"
}
