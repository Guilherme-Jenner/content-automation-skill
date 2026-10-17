#!/usr/bin/env bash
# Testes de edit-recorded.sh --variants (várias variantes de um mesmo bruto, editor local)

_er() { CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# _setup <dir de trabalho> <video> <aprovada1> <aprovada2> <aprovada3>  → grava <dir>/variants-plan.json e roda o propose
_setup() {
  mkdir -p "$1"
  _er "$2" "$1/w" --stage propose >/dev/null 2>&1 || _fail "propose falhou"
  python3 - "$1/variants-plan.json" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
def v(i, tipo, trechos, gancho, ritmo, estilo, aprovada):
    return {"id": i, "tipo": tipo, "trechos": [{"inicio_s": a, "fim_s": b} for a, b in trechos], "gancho": gancho,
            "ritmo": {"min_silencio_s": ritmo[0], "margem_s": ritmo[1]}, "legenda_estilo": estilo,
            "aprovada": aprovada == "true", "achados": ["Hook nos 3 primeiros segundos"]}
plano = {"bruto": sys.argv[2], "editor": "local", "quantidade": 3, "duracao_s": 6.5, "variantes": [
    v("1", "trecho_diferente", [(0, 2)], "Gancho A", (0.6, 0.15), "padrao", sys.argv[3]),
    v("2", "trecho_diferente", [(3.5, 6.5)], "Gancho B", (0.6, 0.15), "padrao", sys.argv[4]),
    v("3", "mesmo_trecho_edicao_diferente", [(0, 2)], "Gancho C", (0.4, 0.05), "destaque", sys.argv[5])]}
json.dump(plano, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_three_variants_produce_three_outputs() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _setup "$d" "$f/tone_silence_tone.mp4" true true true
  _er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" >/dev/null 2>&1 || _fail "apply --variants falhou"
  local i
  for i in 1 2 3; do
    assert_file_exists "$d/w/final-$i.mp4"; assert_file_exists "$d/w/final-$i.srt"
    assert_eq "1080x1920" "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$d/w/final-$i.mp4")" "9:16 da variante $i"
  done
  assert_near 2.0 "$(_dur "$d/w/final-1.mp4")" 0.3 "duração variante 1"
  assert_near 3.0 "$(_dur "$d/w/final-2.mp4")" 0.3 "duração variante 2"
  assert_near 2.0 "$(_dur "$d/w/final-3.mp4")" 0.3 "duração variante 3"
  rm -rf "$d"
}

test_only_approved_variants_run() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _setup "$d" "$f/tone_silence_tone.mp4" true false true
  out=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" 2>&1) || _fail "apply falhou"
  assert_file_exists "$d/w/final-1.mp4"; assert_file_exists "$d/w/final-3.mp4"
  [ ! -e "$d/w/final-2.mp4" ] || _fail "variante não aprovada foi gerada"
  assert_contains "$out" "não aprovada" "resumo cita a variante pulada"
  rm -rf "$d"
}

test_failure_in_middle_keeps_previous_outputs() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _setup "$d" "$f/tone_silence_tone.mp4" true true true
  out=$(CLO_TEST_FAIL_VARIANT=2 _er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" 2>&1) \
    && _fail "deveria sair com erro quando uma variante falha"
  assert_file_exists "$d/w/final-1.mp4"; assert_file_exists "$d/w/final-3.mp4"
  [ ! -e "$d/w/final-2.mp4" ] || _fail "variante que falhou não deveria ter saída"
  assert_near 2.0 "$(_dur "$d/w/final-1.mp4")" 0.3 "variante 1 íntegra"
  assert_contains "$out" "Falharam: 2" "relato das falhas"
  assert_contains "$out" "Concluídas: 1 3" "relato das concluídas"
  [ -z "$(find "$d/w" -name '*.partial.mp4')" ] || _fail "sobrou arquivo parcial"
  rm -rf "$d"
}

test_existing_output_needs_force() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _setup "$d" "$f/tone_silence_tone.mp4" true true true
  echo existente > "$d/w/final-1.mp4"
  msg=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "--force" "mensagem"
  assert_eq existente "$(cat "$d/w/final-1.mp4")" "arquivo intacto"
  [ ! -e "$d/w/final-2.mp4" ] || _fail "nada deveria ter sido gerado antes da recusa"
  _er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" --force >/dev/null 2>&1 || _fail "--force deveria funcionar"
  rm -rf "$d"
}

test_invalid_plan_rejected_before_any_work() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _setup "$d" "$f/tone_silence_tone.mp4" true true true
  python3 - "$d/variants-plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["quantidade"] = 6
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"))
PY
  msg=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "5" "cita o limite"
  [ ! -e "$d/w/final-1.mp4" ] || _fail "nada deveria ser gerado"
  rm -rf "$d"
}

test_katana_editor_not_implemented_yet() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _setup "$d" "$f/tone_silence_tone.mp4" true true true
  python3 - "$d/variants-plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["editor"] = "katana"
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"))
PY
  msg=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/variants-plan.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "ainda não implementado" "mensagem"
  rm -rf "$d"
}

test_relative_paths_work() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  mkdir -p "$d/Meus Vídeos"; cp "$f/tone_silence_tone.mp4" "$d/Meus Vídeos/in.mp4"
  (cd "$d" && CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "Meus Vídeos/in.mp4" "trab rel" --stage propose >/dev/null 2>&1) || _fail "propose falhou"
  python3 - "$d/variants-plan.json" "$d/Meus Vídeos/in.mp4" <<'PY'
import json, sys
v = {"id": "1", "tipo": "trecho_diferente", "trechos": [{"inicio_s": 0, "fim_s": 2}], "gancho": "A",
     "ritmo": {"min_silencio_s": 0.6, "margem_s": 0.15}, "legenda_estilo": "padrao", "aprovada": True, "achados": ["x"]}
json.dump({"bruto": sys.argv[2], "editor": "local", "quantidade": 1, "duracao_s": 6.5, "variantes": [v]},
          open(sys.argv[1], "w", encoding="utf-8"))
PY
  (cd "$d" && CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "Meus Vídeos/in.mp4" "trab rel" --stage apply --variants variants-plan.json >/dev/null 2>&1) \
    || _fail "apply --variants com caminhos relativos falhou"
  assert_file_exists "$d/trab rel/final-1.mp4"
  rm -rf "$d"
}

test_subtitle_styles() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  cp "$ROOT/tests/data/transcript_fake.json" "$d/t.json"
  bash "$ROOT/scripts/subtitles.sh" "$f/no_silence.mp4" "$d/t.json" "$d/o.mp4" --style destaque >/dev/null 2>&1 || _fail "estilo destaque falhou"
  assert_file_exists "$d/o.mp4"
  bash "$ROOT/scripts/subtitles.sh" "$f/no_silence.mp4" "$d/t.json" "$d/p.mp4" --style inexistente >/dev/null 2>&1 && _fail "estilo desconhecido deveria falhar"
  rm -rf "$d"
}
