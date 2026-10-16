#!/usr/bin/env bash
# Testes de scripts/retime_transcript.py e do pipeline scripts/edit-recorded.sh

_er() { CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

_approve() { # plano.json
  python3 - "$1" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["approved"] = True
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_retime_shifts_drops_and_clips() {
  local d; d="$(mktemp -d)"
  printf '%s' '{"idioma":"pt","segmentos":[
    {"inicio_s":0,"fim_s":1,"texto":"antes"},
    {"inicio_s":2.2,"fim_s":2.8,"texto":"dentro do corte"},
    {"inicio_s":2.5,"fim_s":4.5,"texto":"parcial"},
    {"inicio_s":5,"fim_s":6,"texto":"depois"}]}' > "$d/t.json"
  printf '%s' '{"video":"x.mp4","duracao_s":6.5,"approved":true,"cortes":[{"inicio_s":2,"fim_s":3.5,"motivo":"a"}]}' > "$d/p.json"
  python3 "$ROOT/scripts/retime_transcript.py" "$d/t.json" "$d/p.json" > "$d/o.json" || _fail "retime falhou"
  assert_eq 3 "$(json_get "$d/o.json" "len(d['segmentos'])")" "segmento totalmente cortado some"
  assert_eq "antes" "$(json_get "$d/o.json" "d['segmentos'][0]['texto']")" "primeiro"
  assert_near 2.0 "$(json_get "$d/o.json" "d['segmentos'][1]['inicio_s']")" 0.001 "parcial começa no ponto do corte"
  assert_near 3.0 "$(json_get "$d/o.json" "d['segmentos'][1]['fim_s']")" 0.001 "parcial termina deslocado"
  assert_near 3.5 "$(json_get "$d/o.json" "d['segmentos'][2]['inicio_s']")" 0.001 "depois deslocado"
  rm -rf "$d"
}

test_propose_creates_unapproved_plan() {
  local f out; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _er "$f/tone_silence_tone.mp4" "$out/w" --stage propose >/dev/null 2>&1 || _fail "propose falhou"
  assert_file_exists "$out/w/transcript.json"
  assert_file_exists "$out/w/cut-plan.json"
  assert_eq False "$(json_get "$out/w/cut-plan.json" "d['approved']")" "não aprovado"
  rm -rf "$out"
}

test_apply_without_approval_fails() {
  local f out msg; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _er "$f/tone_silence_tone.mp4" "$out/w" --stage propose >/dev/null 2>&1
  msg=$(_er "$f/tone_silence_tone.mp4" "$out/w" --stage apply 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "aprovado" "mensagem"
  [ ! -e "$out/w/final.mp4" ] || _fail "não deveria gerar final.mp4"
  rm -rf "$out"
}

test_full_pipeline_outputs() {
  local f out cut lufs; f="$(fixtures_dir)"; out="$(mktemp -d)"
  _er "$f/tone_silence_tone.mp4" "$out/w" --stage propose >/dev/null 2>&1 || _fail "propose falhou"
  _approve "$out/w/cut-plan.json"
  _er "$f/tone_silence_tone.mp4" "$out/w" --stage apply >/dev/null 2>&1 || _fail "apply falhou"
  assert_file_exists "$out/w/final.mp4"
  assert_file_exists "$out/w/final.srt"
  assert_eq "1080x1920" "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$out/w/final.mp4")" "9:16"
  cut="$(json_get "$out/w/cut-plan.json" "sum(c['fim_s']-c['inicio_s'] for c in d['cortes'])")"
  assert_near "$(python3 -c "print(6.5-$cut)")" "$(_dur "$out/w/final.mp4")" 0.2 "duração = original − cortes"
  lufs=$(ffmpeg -hide_banner -nostats -i "$out/w/final.mp4" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 \
    | python3 -c "
import sys, json, re
print(json.loads(re.search(r'\{[^{}]*\"input_i\"[^{}]*\}', sys.stdin.read(), re.S).group(0))['input_i'])")
  assert_near -14 "$lufs" 1.5 "loudness"
  assert_contains "$(cat "$out/w/final.srt")" "Hoje vou mostrar" "legenda do trecho após o corte"
  rm -rf "$out"
}

test_skills_require_approval_and_research() {
  local s; s=$(cat "$ROOT/skills/edit-recorded/SKILL.md" 2>/dev/null) || _fail "skill edit-recorded ausente"
  assert_contains "$s" "name: edit-recorded" "frontmatter"
  assert_contains "$s" "research.json" "exige pesquisa"
  assert_contains "$s" "brief de edição" "exige brief de edição"
  assert_contains "$s" "approved" "gate de aprovação"
  assert_contains "$s" "caminho do arquivo" "entrada por caminho"
}
