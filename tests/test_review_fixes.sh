#!/usr/bin/env bash
# Regressões dos achados da revisão final da fase 1 (C1, I1–I6)

_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
_approve() {
  python3 - "$1" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["approved"] = True
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

# C1 ------------------------------------------------------------------------
test_subtitles_works_with_relative_paths() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  cp "$f/no_silence.mp4" "$d/in.mp4"; cp "$ROOT/tests/data/transcript_fake.json" "$d/t.json"
  (cd "$d" && bash "$ROOT/scripts/subtitles.sh" in.mp4 t.json out.mp4 >/dev/null 2>&1) || _fail "subtitles.sh falhou com caminhos relativos"
  assert_file_exists "$d/out.mp4"
  rm -rf "$d"
}

test_edit_recorded_apply_with_relative_paths() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  mkdir -p "$d/Meus Vídeos"; cp "$f/tone_silence_tone.mp4" "$d/Meus Vídeos/in.mp4"
  (cd "$d" && CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "Meus Vídeos/in.mp4" "trab rel" --stage propose >/dev/null 2>&1) \
    || _fail "propose com caminhos relativos falhou"
  _approve "$d/trab rel/cut-plan.json"
  (cd "$d" && CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "Meus Vídeos/in.mp4" "trab rel" --stage apply >/dev/null 2>&1) \
    || _fail "apply com caminhos relativos falhou"
  assert_file_exists "$d/trab rel/final.mp4"
  assert_file_exists "$d/trab rel/final.srt"
  rm -rf "$d"
}

# I1 ------------------------------------------------------------------------
test_propose_refuses_to_overwrite_approved_plan() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$f/tone_silence_tone.mp4" "$d/w" --stage propose >/dev/null 2>&1
  _approve "$d/w/cut-plan.json"
  msg=$(CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$f/tone_silence_tone.mp4" "$d/w" --stage propose 2>&1) \
    && _fail "propose deveria recusar sobrescrever"
  assert_contains "$msg" "--force" "mensagem"
  assert_eq True "$(json_get "$d/w/cut-plan.json" "d['approved']")" "plano aprovado intacto"
  CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$f/tone_silence_tone.mp4" "$d/w" --stage propose --force >/dev/null 2>&1 \
    || _fail "--force deveria permitir"
  rm -rf "$d"
}

test_scripts_refuse_existing_output_without_force() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  cp "$ROOT/tests/data/transcript_fake.json" "$d/t.json"
  local s
  for s in "silence-detect.sh|$f/tone_silence_tone.mp4|$d/o1.json" \
           "normalize-audio.sh|$f/no_silence.mp4|$d/o2.mp4" \
           "reframe-9x16.sh|$f/no_silence.mp4|$d/o3.mp4"; do
    IFS='|' read -r name in out <<< "$s"
    echo existente > "$out"
    bash "$ROOT/scripts/$name" "$in" "$out" >/dev/null 2>&1 && _fail "$name sobrescreveu sem --force"
    assert_eq existente "$(cat "$out")" "$name deixou o arquivo intacto"
  done
  echo existente > "$d/o4.mp4"
  bash "$ROOT/scripts/subtitles.sh" "$f/no_silence.mp4" "$d/t.json" "$d/o4.mp4" >/dev/null 2>&1 && _fail "subtitles.sh sobrescreveu sem --force"
  assert_eq existente "$(cat "$d/o4.mp4")" "subtitles.sh intacto"
  rm -rf "$d"
}

# I2 ------------------------------------------------------------------------
test_cut_plan_must_match_the_video() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  printf '{"video":"x.mp4","duracao_s":100,"approved":true,"cortes":[{"inicio_s":10,"fim_s":20,"motivo":"a"}]}' > "$d/p.json"
  msg=$(bash "$ROOT/scripts/apply-cuts.sh" "$f/tone_silence_tone.mp4" "$d/p.json" "$d/o.mp4" 2>&1) && _fail "deveria recusar duração divergente"
  assert_contains "$msg" "duração" "mensagem"
  CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$f/tone_silence_tone.mp4" "$d/w" --stage propose >/dev/null 2>&1
  _approve "$d/w/cut-plan.json"
  msg=$(CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$f/no_silence.mp4" "$d/w" --stage apply 2>&1) && _fail "apply com outro vídeo deveria recusar"
  assert_contains "$msg" "outro vídeo" "mensagem"
  rm -rf "$d"
}

# I3 ------------------------------------------------------------------------
test_short_video_rejected_with_clear_message() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=25:duration=0.5 -f lavfi -i sine=frequency=440:duration=0.5 \
    -c:v libx264 -pix_fmt yuv420p -c:a aac "$d/curto.mp4"
  msg=$(CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$d/curto.mp4" "$d/w" --stage propose 2>&1) && _fail "propose deveria recusar"
  assert_contains "$msg" "menos de 1 s" "mensagem"
  printf '{"video":"x","duracao_s":6.5,"approved":true,"cortes":[{"inicio_s":0.2,"fim_s":6.3,"motivo":"a"}]}' > "$d/p.json"
  msg=$(bash "$ROOT/scripts/apply-cuts.sh" "$f/tone_silence_tone.mp4" "$d/p.json" "$d/o.mp4" 2>&1) && _fail "apply-cuts deveria recusar sobra < 1 s"
  assert_contains "$msg" "menos de 1 s" "mensagem do apply"
  rm -rf "$d"
}

# I4 ------------------------------------------------------------------------
test_empty_transcript_keeps_video_without_subtitles() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  printf '{"idioma":"pt","segmentos":[]}' > "$d/t.json"
  msg=$(bash "$ROOT/scripts/subtitles.sh" "$f/no_silence.mp4" "$d/t.json" "$d/o.mp4" 2>&1) || _fail "deveria concluir sem legenda"
  assert_contains "$msg" "nenhuma fala" "aviso"
  assert_file_exists "$d/o.mp4"
  assert_near 4 "$(_dur "$d/o.mp4")" 0.15 "vídeo mantido"
  [ ! -s "$d/o.srt" ] || _fail "não deveria sobrar .srt com conteúdo"
  rm -rf "$d"
}

# I5 / I6 -------------------------------------------------------------------
test_skills_use_plugin_root_for_scripts() {
  local s bad
  for s in "$ROOT"/skills/*/SKILL.md; do
    bad=$(grep -nE '(^|[ `"])(bash|python3) scripts/' "$s" || true)
    [ -z "$bad" ] || _fail "$(basename "$(dirname "$s")") usa caminho relativo: $bad"
  done
  assert_contains "$(cat "$ROOT/skills/edit-recorded/SKILL.md")" '${CLAUDE_PLUGIN_ROOT}/scripts/' "usa a raiz do plugin"
}

test_edit_skill_merges_and_validates_cuts_before_showing() {
  local s; s=$(cat "$ROOT/skills/edit-recorded/SKILL.md")
  assert_contains "$s" "validate_cutplan.py" "valida o plano antes de mostrar"
  assert_contains "$s" "junte" "orienta fundir cortes sobrepostos"
  assert_contains "$s" "editando" "ajustes editam o plano, não rodam propose de novo"
}
