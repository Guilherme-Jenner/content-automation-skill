#!/usr/bin/env bash
# Regressões dos achados da revisão da Fase 1b (Etapa 1)

_er() { CLO_TRANSCRIBER=fake bash "$ROOT/scripts/edit-recorded.sh" "$@"; }

# _plan <saida> <video> <expressão python que altera p>
_plan() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
def v(i, trechos, g, estilo="padrao", tipo="trecho_diferente", ritmo=(0.6, 0.15)):
    return {"id": i, "tipo": tipo, "trechos": [{"inicio_s": a, "fim_s": b} for a, b in trechos], "gancho": g,
            "ritmo": {"min_silencio_s": ritmo[0], "margem_s": ritmo[1]}, "legenda_estilo": estilo, "aprovada": True, "achados": ["x"]}
p = {"bruto": sys.argv[2], "editor": "local", "quantidade": 2, "duracao_s": 6.5,
     "variantes": [v("1", [(0, 2)], "A"), v("2", [(3.5, 6.5)], "B")]}
exec(sys.argv[3])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

# C1 ------------------------------------------------------------------------
test_unsafe_variant_ids_rejected_by_validator() {
  local d id out; d="$(mktemp -d)"
  for id in '$(touch${IFS}PWNED)' '*' 'a b' '..' 'x/y' '' "a'b"; do
    _plan "$d/p.json" "v.mp4" "p['variantes'][0]['id'] = $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$id")"
    out=$(python3 "$ROOT/scripts/validate_variants.py" "$d/p.json" 2>&1) && _fail "id inseguro aceito: '$id'"
    assert_contains "$out" "id" "mensagem cita o id ('$id')"
  done
  _plan "$d/p.json" "v.mp4" "p['variantes'][0]['id'] = 'A'; p['variantes'][1]['id'] = 'a'"
  out=$(python3 "$ROOT/scripts/validate_variants.py" "$d/p.json" 2>&1) && _fail "ids que só diferem por maiúscula deveriam colidir"
  assert_contains "$out" "repetidos" "mensagem"
  rm -rf "$d"
}

test_command_substitution_in_id_does_not_execute() {
  local f d; f="$(fixtures_dir)"; d="$(mktemp -d)"
  mkdir -p "$d/run"
  _er "$f/tone_silence_tone.mp4" "$d/w" --stage propose >/dev/null 2>&1
  _plan "$d/p.json" "$f/tone_silence_tone.mp4" "p['variantes'][0]['id'] = '\$(touch\${IFS}PWNED)'"
  (cd "$d/run" && _er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/p.json" >/dev/null 2>&1) && _fail "deveria recusar"
  [ ! -e "$d/run/PWNED" ] || _fail "o id foi executado como comando"
  rm -rf "$d"
}

# I2 ------------------------------------------------------------------------
test_failed_step_stops_the_variant_without_cascade() {
  local f d out; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _er "$f/tone_silence_tone.mp4" "$d/w" --stage propose >/dev/null 2>&1
  # trecho [1.5,3.5] soma 2 s (válido), mas o silêncio 2.15–3.35 deixa só ~0,8 s: o apply-cuts falha depois do merge
  _plan "$d/p.json" "$f/tone_silence_tone.mp4" "p['quantidade'] = 2; p['variantes'] = [v('1', [(0, 2)], 'A'), v('2', [(1.5, 3.5)], 'B')]"
  out=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/p.json" 2>&1) && _fail "deveria sair com erro"
  assert_contains "$out" "menos de 1 s" "a causa real aparece"
  case "$out" in *"não encontrado"*|*"não foi possível ler"*) _fail "etapas seguintes rodaram em cascata: $out" ;; esac
  assert_contains "$out" "Falharam: 2" "relato"
  [ ! -e "$d/w/final-2.mp4" ] || _fail "variante que falhou não deveria ter saída"
  rm -rf "$d"
}

# I3 ------------------------------------------------------------------------
test_existing_srt_needs_force() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _er "$f/tone_silence_tone.mp4" "$d/w" --stage propose >/dev/null 2>&1
  _plan "$d/p.json" "$f/tone_silence_tone.mp4" "pass"
  echo editado > "$d/w/final-1.srt"
  msg=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/p.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "--force" "mensagem"
  assert_eq editado "$(cat "$d/w/final-1.srt")" ".srt intacto"
  rm -rf "$d"
}

# I4 ------------------------------------------------------------------------
test_unknown_caption_style_rejected_before_running() {
  local d out; d="$(mktemp -d)"
  _plan "$d/p.json" "v.mp4" "p['variantes'][0]['legenda_estilo'] = 'Destaque'"
  out=$(python3 "$ROOT/scripts/validate_variants.py" "$d/p.json" 2>&1) && _fail "estilo desconhecido aceito"
  assert_contains "$out" "legenda_estilo" "mensagem"
  rm -rf "$d"
}

# I5 ------------------------------------------------------------------------
test_transcript_from_another_video_rejected() {
  local f d msg; f="$(fixtures_dir)"; d="$(mktemp -d)"
  _er "$f/no_silence.mp4" "$d/w" --stage propose >/dev/null 2>&1
  _plan "$d/p.json" "$f/tone_silence_tone.mp4" "pass"
  msg=$(_er "$f/tone_silence_tone.mp4" "$d/w" --stage apply --variants "$d/p.json" 2>&1) && _fail "deveria recusar"
  assert_contains "$msg" "outro vídeo" "mensagem"
  rm -rf "$d"
}

# I6 ------------------------------------------------------------------------
test_identical_edit_variants_warn_and_skill_is_honest_about_hooks() {
  local d out s; d="$(mktemp -d)"
  _plan "$d/p.json" "v.mp4" "p['variantes'] = [v('1', [(0, 3)], 'A', tipo='mesmo_trecho_edicao_diferente'), v('2', [(0, 3)], 'B', tipo='mesmo_trecho_edicao_diferente')]"
  out=$(python3 "$ROOT/scripts/validate_variants.py" "$d/p.json" 2>&1) || _fail "aviso não é erro"
  assert_contains "$out" "aviso" "avisa edição idêntica"
  s=$(cat "$ROOT/skills/edit-recorded/SKILL.md")
  assert_contains "$s" "não é renderizado" "a skill diz que o gancho não é renderizado pelo editor local"
  rm -rf "$d"
}
