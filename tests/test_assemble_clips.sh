#!/usr/bin/env bash
# Testes de scripts/assemble-clips.sh

_as() { bash "$ROOT/scripts/assemble-clips.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# cor do pixel central de um quadro no instante t: imprime "R G B"
_pixel() {
  ffmpeg -v error -ss "$2" -i "$1" -frames:v 1 -vf "scale=1:1" -f rawvideo -pix_fmt rgb24 - </dev/null | python3 -c "
import sys
b = sys.stdin.buffer.read(3)
print(*b)"
}

# _prep <dir> [audio: sim|nao]  → g.json (c1 4 s vermelho, c2 5 s verde, c3 6 s azul) + clips/ + manifesto
_prep() {
  local d="$1" audio="${2:-nao}"
  mkdir -p "$d/w/clips"
  python3 - "$d/g.json" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}, {"id": "c3", "prompt": "c", "duracao_s": 6}]},
          open(sys.argv[1], "w", encoding="utf-8"))
PY
  local id cor dur
  for pair in "c1 red 4" "c2 green 5" "c3 blue 6"; do
    read -r id cor dur <<EOP
$pair
EOP
    if [ "$audio" = sim ]; then
      ffmpeg -v error -y -f lavfi -i "color=c=$cor:size=480x854:rate=25:duration=$dur" -f lavfi -i "sine=frequency=300:duration=$dur" \
        -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$d/w/clips/$id.mp4" </dev/null
    else
      ffmpeg -v error -y -f lavfi -i "color=c=$cor:size=480x854:rate=25:duration=$dur" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/$id.mp4" </dev/null
    fi
    python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" "$id" "clips/$id.mp4" 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key "$id")" fake >/dev/null
  done
}

test_clips_are_joined_in_plan_order_and_reframed() {
  local d p; d="$(mktemp -d)"; _prep "$d"
  _as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" >/dev/null 2>&1 || _fail "assemble falhou"
  assert_near 15 "$(_dur "$d/final.mp4")" 0.3 "4 + 5 + 6 s"
  assert_eq "1080x1920" "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$d/final.mp4")" "9:16"
  p=$(_pixel "$d/final.mp4" 2);  set -- $p; [ "$1" -gt 150 ] && [ "$2" -lt 100 ] && [ "$3" -lt 100 ] || _fail "em 2 s deveria ser vermelho (c1): $p"
  p=$(_pixel "$d/final.mp4" 6);  set -- $p; [ "$2" -gt 100 ] && [ "$1" -lt 100 ] || _fail "em 6 s deveria ser verde (c2): $p"
  p=$(_pixel "$d/final.mp4" 12); set -- $p; [ "$3" -gt 150 ] && [ "$1" -lt 100 ] || _fail "em 12 s deveria ser azul (c3): $p"
  rm -rf "$d"
}

test_order_follows_the_plan_not_the_manifest() {
  local d p; d="$(mktemp -d)"; _prep "$d"
  python3 - "$d/g.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"].reverse()
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"))
PY
  _as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" >/dev/null 2>&1 || _fail "assemble falhou"
  p=$(_pixel "$d/final.mp4" 2); set -- $p; [ "$3" -gt 150 ] || _fail "plano invertido: em 2 s deveria ser azul (c3): $p"
  rm -rf "$d"
}

test_missing_clip_or_changed_file_is_refused() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  python3 - "$d/w/clips-manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8")); del m["clips"]["c2"]
json.dump(m, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(_as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" 2>&1) && _fail "cena sem clipe aceita"
  assert_contains "$out" "c2" "cita a cena"
  [ ! -e "$d/final.mp4" ] || _fail "não deveria gerar saída"
  rm -rf "$d"; d="$(mktemp -d)"; _prep "$d"
  echo adulterado > "$d/w/clips/c1.mp4"
  out=$(_as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" 2>&1) && _fail "arquivo alterado aceito"
  assert_contains "$out" "hash" "mensagem"
  [ ! -e "$d/final.mp4" ] || _fail "não deveria gerar saída"
  rm -rf "$d"
}

test_audio_is_kept_when_all_clips_have_it() {
  local d; d="$(mktemp -d)"; _prep "$d" sim
  _as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" >/dev/null 2>&1 || _fail "assemble com áudio falhou"
  assert_eq audio "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$d/final.mp4")" "tem áudio"
  assert_near 15 "$(_dur "$d/final.mp4")" 0.3 "duração total"
  rm -rf "$d"
}

test_mixed_audio_and_silent_clips_are_refused() {
  local d out; d="$(mktemp -d)"; _prep "$d" sim
  ffmpeg -v error -y -f lavfi -i "color=c=green:size=480x854:rate=25:duration=5" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/c2.mp4" </dev/null
  python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" c2 clips/c2.mp4 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key c2)" fake >/dev/null
  out=$(_as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" 2>&1) && _fail "clipes com e sem áudio misturados aceitos"
  assert_contains "$out" "áudio" "mensagem"
  rm -rf "$d"
}

test_existing_output_needs_force() {
  local d out; d="$(mktemp -d)"; _prep "$d"; echo existente > "$d/final.mp4"
  out=$(_as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" 2>&1) && _fail "sobrescreveu sem --force"
  assert_contains "$out" "--force" "mensagem"
  assert_eq existente "$(cat "$d/final.mp4")" "arquivo intacto"
  _as "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" --force >/dev/null 2>&1 || _fail "--force deveria permitir"
  rm -rf "$d"
}

test_relative_paths_and_spaces() {
  local d; d="$(mktemp -d)/pasta com espaço é"; _prep "$d"
  (cd "$d" && bash "$ROOT/scripts/assemble-clips.sh" g.json w/clips-manifest.json "vídeo final.mp4" >/dev/null 2>&1) || _fail "caminhos relativos falharam"
  assert_file_exists "$d/vídeo final.mp4"
  rm -rf "$d"
}
