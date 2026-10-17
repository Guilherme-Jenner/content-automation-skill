#!/usr/bin/env bash
# Regressões dos achados da revisão da Fase 3b (I1–I4)

_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# conta as "bandas" de texto (linhas visíveis) num quadro de um vídeo 1080x1920 no instante 1 s
_bandas() {
  ffmpeg -v error -ss 1 -i "$1" -frames:v 1 -vf "scale=216:384" -f rawvideo -pix_fmt gray - </dev/null | python3 -c "
import sys
raw = sys.stdin.buffer.read(); w, h = 216, 384
rows = [sum(raw[y*w:(y+1)*w]) for y in range(h)]
m = max(rows) or 1
bandas, atual, gap = 0, False, 0
for r in rows:
    if r > m * 0.12:
        if not atual: bandas += 1
        atual, gap = True, 0
    else:
        gap += 1
        if gap >= 5: atual = False  # folga entre linhas; descendentes (g, ç) não partem uma linha
print(bandas)"
}

# I1 ------------------------------------------------------------------------
test_wrapping_width_follows_the_style_so_burned_captions_use_at_most_3_lines() {
  local d est max texto n; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "color=c=black:size=1080x1920:rate=25:duration=2" -c:v libx264 -pix_fmt yuv420p -an "$d/base.mp4" </dev/null
  for est in padrao destaque discreto; do
    texto=$(python3 "$ROOT/scripts/caption_styles.py" prefixo "$est" "Sua rotina vive bagunçada e você nunca acha tempo para o que importa de verdade, então o Clo App organiza tudo por você agora")
    texto=$(python3 -c "import sys; print(sys.argv[1].strip())" "$texto")
    python3 -c "import json,sys; open(sys.argv[1],'w',encoding='utf-8').write(json.dumps({'idioma':'pt','segmentos':[{'inicio_s':0.1,'fim_s':1.9,'texto':sys.argv[2]}]}, ensure_ascii=False))" "$d/t.json" "$texto"
    bash "$ROOT/scripts/subtitles.sh" "$d/base.mp4" "$d/t.json" "$d/o_$est.mp4" --style "$est" >/dev/null 2>&1 || _fail "subtitles.sh falhou ($est)"
    n="$(_bandas "$d/o_$est.mp4")"
    [ "$n" -le 3 ] || _fail "estilo $est: texto de ${#texto} caracteres ocupou $n linhas na tela (máximo 3)"
  done
  rm -rf "$d"
}

test_text_limit_is_per_style_and_matches_three_rendered_lines() {
  local d out; d="$(mktemp -d)"
  python3 - "$d" <<'PY'
import json, sys, os
d = sys.argv[1]
os.makedirs(d + "/w/clips", exist_ok=True)
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}]}, open(d + "/g.json", "w", encoding="utf-8"))
PY
  ffmpeg -v error -y -f lavfi -i "color=c=red:size=480x854:rate=25:duration=4" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/c1.mp4" </dev/null
  python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" c1 clips/c1.mp4 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key c1)" fake >/dev/null
  local est max
  for est in padrao destaque discreto; do
    max=$(python3 "$ROOT/scripts/caption_styles.py" max "$est")
    python3 -c "import json,sys; open(sys.argv[1],'w',encoding='utf-8').write(json.dumps({'estilo':sys.argv[2],'cenas':[{'cena':'c1','legendas':[{'texto':'x'*int(sys.argv[3])}]}]}))" "$d/c.json" "$est" "$max"
    python3 "$ROOT/scripts/captions_to_transcript.py" "$d/c.json" "$d/g.json" "$d/w/clips-manifest.json" >/dev/null 2>&1 || _fail "$est: exatamente $max caracteres deveria passar"
    python3 -c "import json,sys; open(sys.argv[1],'w',encoding='utf-8').write(json.dumps({'estilo':sys.argv[2],'cenas':[{'cena':'c1','legendas':[{'texto':'x'*(int(sys.argv[3])+1)}]}]}))" "$d/c.json" "$est" "$max"
    out=$(python3 "$ROOT/scripts/captions_to_transcript.py" "$d/c.json" "$d/g.json" "$d/w/clips-manifest.json" 2>&1) && _fail "$est: $((max + 1)) caracteres deveria ser recusado"
    assert_contains "$out" "$max" "a mensagem cita o limite do estilo $est"
  done
  rm -rf "$d"
}

# I2 ------------------------------------------------------------------------
test_add_soundtrack_check_only_validates_without_producing_anything() {
  local d out; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "testsrc2=size=480x854:rate=25:duration=3" -c:v libx264 -pix_fmt yuv420p -an "$d/v.mp4" </dev/null
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=2" "$d/ok.wav" </dev/null
  ffmpeg -v error -y -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 2 "$d/mudo.wav" </dev/null
  bash "$ROOT/scripts/add-soundtrack.sh" "$d/v.mp4" "$d/ok.wav" "$d/o.mp4" --check-only >/dev/null 2>&1 || _fail "entrada válida deveria passar no --check-only"
  [ ! -e "$d/o.mp4" ] || _fail "--check-only não pode produzir saída"
  out=$(bash "$ROOT/scripts/add-soundtrack.sh" "$d/v.mp4" "$d/mudo.wav" "$d/o.mp4" --check-only 2>&1) && _fail "música silenciosa passou no --check-only"
  assert_contains "$out" "silenciosa" "mensagem"
  out=$(bash "$ROOT/scripts/add-soundtrack.sh" "$d/v.mp4" "$d/ok.wav" "$d/o.mp4" --volume-db 5 --check-only 2>&1) && _fail "volume inválido passou no --check-only"
  assert_contains "$out" "volume" "mensagem"
  rm -rf "$d"
}

test_edit_generated_checks_the_music_before_any_heavy_step() {
  local f="$ROOT/scripts/edit-generated.sh" a b
  a=$(grep -n -e '--check-only' "$f" | head -1 | cut -d: -f1)
  b=$(grep -n -e 'reframe-9x16.sh" "\$cur"' "$f" | head -1 | cut -d: -f1)
  [ -n "$a" ] || _fail "edit-generated.sh não usa add-soundtrack.sh --check-only"
  [ -n "$b" ] && [ "$a" -lt "$b" ] || _fail "a validação da música ($a) deve vir antes do reenquadramento ($b)"
}

# I3 ------------------------------------------------------------------------
_prep_montado() { # <dir> → gen-plan (c1 4 s, c2 5 s), clipes reais, manifesto e montado.mp4
  local d="$1" id cor dur
  mkdir -p "$d/w/clips"
  python3 - "$d/g.json" "$d/c.json" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}]}, open(sys.argv[1], "w", encoding="utf-8"))
json.dump({"estilo": "padrao", "cenas": [{"cena": "c2", "legendas": [{"texto": "Organiza tudo"}]}]}, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  for pair in "c1 red 4" "c2 green 5"; do
    read -r id cor dur <<EOP
$pair
EOP
    ffmpeg -v error -y -f lavfi -i "color=c=$cor:size=480x854:rate=25:duration=$dur" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/$id.mp4" </dev/null
    python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" "$id" "clips/$id.mp4" 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key "$id")" fake >/dev/null
  done
  bash "$ROOT/scripts/assemble-clips.sh" "$d/g.json" "$d/w/clips-manifest.json" "$d/montado.mp4" >/dev/null 2>&1 || _fail "assemble-clips falhou no preparo"
}
_eg() { local d="$1"; shift; bash "$ROOT/scripts/edit-generated.sh" "$d/montado.mp4" "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" "$@"; }

test_assembled_video_must_match_the_manifest_and_the_plan() {
  local d out; d="$(mktemp -d)"; _prep_montado "$d"
  _eg "$d" --captions "$d/c.json" >/dev/null 2>&1 || _fail "caso feliz deveria passar"
  rm -f "$d/final.mp4" "$d/final.srt"
  # c2 foi regerado com OUTRA duração depois da montagem (mesma versão do plano, hash atualizado no manifesto)
  ffmpeg -v error -y -f lavfi -i "color=c=green:size=480x854:rate=25:duration=6.5" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/c2.mp4" </dev/null
  python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" c2 clips/c2.mp4 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key c2)" fake >/dev/null
  out=$(_eg "$d" --captions "$d/c.json" 2>&1) && _fail "vídeo montado com duração diferente dos clipes aceito"
  assert_contains "$out" "montado" "mensagem"
  [ ! -e "$d/final.mp4" ] || _fail "não deveria gerar saída"
  rm -rf "$d"; d="$(mktemp -d)"; _prep_montado "$d"
  python3 - "$d/g.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"][1]["prompt"] = "outro prompt"
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(_eg "$d" --captions "$d/c.json" 2>&1) && _fail "plano alterado depois da geração aceito"
  assert_contains "$out" "outra versão do plano" "mensagem"
  rm -rf "$d"
}

# I4 ------------------------------------------------------------------------
test_volume_has_no_effect_on_a_silent_video_and_the_user_is_told() {
  local d out; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "testsrc2=size=480x854:rate=25:duration=3" -c:v libx264 -pix_fmt yuv420p -an "$d/mudo.mp4" </dev/null
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=2" "$d/m.wav" </dev/null
  out=$(bash "$ROOT/scripts/add-soundtrack.sh" "$d/mudo.mp4" "$d/m.wav" "$d/o.mp4" --volume-db -30 2>&1) || _fail "add-soundtrack falhou"
  assert_contains "$out" "aviso" "avisa que o volume não muda nada em vídeo mudo"
  assert_contains "$out" "normaliz" "explica que a trilha sai normalizada"
  out=$(bash "$ROOT/scripts/add-soundtrack.sh" "$d/mudo.mp4" "$d/m.wav" "$d/p.mp4" 2>&1) || _fail "add-soundtrack falhou"
  case "$out" in *aviso*) _fail "sem --volume-db explícito não há o que avisar" ;; esac
  assert_contains "$(cat "$ROOT/skills/edit-generated/SKILL.md")" "só tem efeito" "a SKILL explica quando o volume vale"
  rm -rf "$d"
}
