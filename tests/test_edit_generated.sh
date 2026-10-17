#!/usr/bin/env bash
# Testes de scripts/edit-generated.sh (legendas e trilha sobre o vídeo montado do modo gerado)

_eg() { bash "$ROOT/scripts/edit-generated.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
_dims() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$1"; }
_nstreams() { ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$1" | wc -l | tr -d ' '; }

# _prep <dir> → gen-plan (c1 4 s, c2 5 s, c3 6 s), clipes, manifesto, montado.mp4 (1080x1920, 15 s), captions c.json e música m.wav
_prep() {
  local d="$1" id cor dur
  mkdir -p "$d/w/clips"
  python3 - "$d/g.json" "$d/c.json" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}, {"id": "c3", "prompt": "c", "duracao_s": 6}]},
          open(sys.argv[1], "w", encoding="utf-8"))
json.dump({"estilo": "destaque", "cenas": [
    {"cena": "c1", "legendas": [{"texto": "Sua rotina vive bagunçada?"}]},
    {"cena": "c2", "legendas": [{"texto": "O Clo App organiza tudo", "inicio_s": 0.5, "fim_s": 3}]}]},
    open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  for pair in "c1 red 4" "c2 green 5" "c3 blue 6"; do
    read -r id cor dur <<EOP
$pair
EOP
    ffmpeg -v error -y -f lavfi -i "color=c=$cor:size=480x854:rate=25:duration=$dur" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/$id.mp4" </dev/null
    python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" "$id" "clips/$id.mp4" 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key "$id")" fake >/dev/null
  done
  bash "$ROOT/scripts/assemble-clips.sh" "$d/g.json" "$d/w/clips-manifest.json" "$d/montado.mp4" >/dev/null 2>&1 || _fail "assemble-clips falhou no preparo"
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=4" "$d/m.wav" </dev/null
}
_run() { local d="$1"; shift; _eg "$d/montado.mp4" "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" "$@"; }

test_captions_only() {
  local d; d="$(mktemp -d)"; _prep "$d"
  _run "$d" --captions "$d/c.json" >/dev/null 2>&1 || _fail "edit-generated falhou"
  assert_file_exists "$d/final.mp4"; assert_file_exists "$d/final.srt"
  assert_near 15 "$(_dur "$d/final.mp4")" 0.3 "duração"
  assert_eq "1080x1920" "$(_dims "$d/final.mp4")" "9:16"
  assert_contains "$(cat "$d/final.srt")" "00:00:00,200 --> 00:00:03,800" "tempo da legenda de c1"
  assert_contains "$(cat "$d/final.srt")" "00:00:04,500 --> 00:00:07,000" "c2 começa em 4 + 0,5"
  assert_contains "$(cat "$d/final.srt")" "O Clo App organiza tudo" "texto"
  assert_eq 0 "$(_nstreams "$d/final.mp4")" "sem trilha, segue mudo"
  rm -rf "$d"
}

test_music_only() {
  local d; d="$(mktemp -d)"; _prep "$d"
  _run "$d" --music "$d/m.wav" >/dev/null 2>&1 || _fail "edit-generated falhou"
  assert_file_exists "$d/final.mp4"
  [ ! -e "$d/final.srt" ] || _fail "sem legendas não deveria criar .srt"
  assert_eq 1 "$(_nstreams "$d/final.mp4")" "tem áudio"
  assert_near 15 "$(_dur "$d/final.mp4")" 0.3 "duração"
  rm -rf "$d"
}

test_captions_and_music() {
  local d; d="$(mktemp -d)"; _prep "$d"
  _run "$d" --captions "$d/c.json" --music "$d/m.wav" --volume-db -12 >/dev/null 2>&1 || _fail "edit-generated falhou"
  assert_file_exists "$d/final.mp4"; assert_file_exists "$d/final.srt"
  assert_eq 1 "$(_nstreams "$d/final.mp4")" "tem áudio"
  assert_eq "1080x1920" "$(_dims "$d/final.mp4")" "9:16"
  rm -rf "$d"
}

test_requires_captions_or_music() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  out=$(_run "$d" 2>&1) && _fail "sem nenhuma opção deveria falhar"
  assert_contains "$out" "--captions" "mensagem"
  [ ! -e "$d/final.mp4" ] || _fail "não deveria criar saída"
  rm -rf "$d"
}

test_invalid_inputs_are_refused_before_any_output() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  python3 - "$d/c.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8")); p["cenas"][0]["legendas"][0]["fim_s"] = 99
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out=$(_run "$d" --captions "$d/c.json" --music "$d/m.wav" 2>&1) && _fail "legenda fora da cena aceita"
  assert_contains "$out" "fora da cena" "mensagem"
  echo "não é áudio" > "$d/falso.wav"
  out=$(_run "$d" --music "$d/falso.wav" 2>&1) && _fail "música inválida aceita"
  assert_contains "$out" "música" "mensagem"
  [ ! -e "$d/final.mp4" ] && [ ! -e "$d/final.srt" ] || _fail "nenhuma recusa deveria deixar saída"
  [ -z "$(find "$d" -maxdepth 1 -name '.*partial*')" ] || _fail "sobrou arquivo parcial"
  rm -rf "$d"
}

test_existing_outputs_need_force() {
  local d out; d="$(mktemp -d)"; _prep "$d"; echo existente > "$d/final.srt"
  out=$(_run "$d" --captions "$d/c.json" 2>&1) && _fail "sobrescreveu o .srt sem --force"
  assert_contains "$out" "--force" "mensagem"
  assert_eq existente "$(cat "$d/final.srt")" "srt intacto"
  [ ! -e "$d/final.mp4" ] || _fail "nada deveria ser gerado antes da recusa"
  _run "$d" --captions "$d/c.json" --force >/dev/null 2>&1 || _fail "--force deveria permitir"
  rm -rf "$d"
}

test_non_vertical_input_is_reframed_to_9x16() {
  local d; d="$(mktemp -d)"; _prep "$d"
  ffmpeg -v error -y -f lavfi -i "color=c=white:size=1280x720:rate=25:duration=15" -c:v libx264 -pix_fmt yuv420p -an "$d/montado.mp4" </dev/null
  _run "$d" --captions "$d/c.json" >/dev/null 2>&1 || _fail "edit-generated falhou"
  assert_eq "1080x1920" "$(_dims "$d/final.mp4")" "reenquadrado"
  rm -rf "$d"
}

test_relative_paths_and_spaces() {
  local d; d="$(mktemp -d)/pasta com espaço é"; _prep "$d"
  (cd "$d" && bash "$ROOT/scripts/edit-generated.sh" montado.mp4 g.json w/clips-manifest.json "vídeo final.mp4" --captions c.json --music m.wav >/dev/null 2>&1) \
    || _fail "caminhos relativos/espaços falharam"
  assert_file_exists "$d/vídeo final.mp4"; assert_file_exists "$d/vídeo final.srt"
  rm -rf "$d"
}
