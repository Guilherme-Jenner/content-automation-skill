#!/usr/bin/env bash
# Minors adiados das fases 3/3b (ledger): áudio misto na montagem, storyboard, NaN, volume, caminho do .srt, saída

_mkclip() { # arquivo cor duração canais(0|1|2)
  local aud=()
  case "$4" in
    0) aud=(-an) ;;
    1) aud=(-f lavfi -i "sine=frequency=330:duration=$3" -ac 1 -c:a aac -shortest) ;;
    2) aud=(-f lavfi -i "sine=frequency=330:duration=$3" -ac 2 -c:a aac -shortest) ;;
  esac
  ffmpeg -v error -y -f lavfi -i "color=c=$2:size=480x854:rate=25:duration=$3" ${aud[@]+"${aud[@]}"} -c:v libx264 -pix_fmt yuv420p "$1" </dev/null
}

# _gen <dir> <audio true|false> <canais c1> <canais c2> → g.json (c1 4 s, c2 5 s), clipes, manifesto
_gen() {
  local d="$1" aud="$2" id cor dur ch
  mkdir -p "$d/w/clips"
  python3 - "$d/g.json" "$aud" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": sys.argv[2] == "true",
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}]},
          open(sys.argv[1], "w", encoding="utf-8"))
PY
  for pair in "c1 red 4 $3" "c2 green 5 $4"; do
    read -r id cor dur ch <<EOP
$pair
EOP
    _mkclip "$d/w/clips/$id.mp4" "$cor" "$dur" "$ch"
    python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" "$id" "clips/$id.mp4" 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key "$id")" fake >/dev/null
  done
}

test_assemble_mixed_channel_layouts_gives_stereo() {
  local d; d="$(mktemp -d)"; _gen "$d" true 1 2
  bash "$ROOT/scripts/assemble-clips.sh" "$d/g.json" "$d/w/clips-manifest.json" "$d/o.mp4" >/dev/null 2>&1 || _fail "montagem falhou"
  assert_eq 2 "$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$d/o.mp4")" "saída estéreo mesmo com o primeiro clipe mono"
  rm -rf "$d"
}

test_storyboard_with_bad_duration_gives_a_clear_error() {
  local d out; d="$(mktemp -d)"
  python3 - "$d/s.json" <<'PY'
import json, sys
json.dump({"modo": "gerado", "cenas": [{"id": "c1", "prompt": "x", "duracao_s": "quatro"}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(python3 "$ROOT/scripts/storyboard_to_genplan.py" "$d/s.json" 2>&1) && _fail "duração em texto aceita"
  assert_contains "$out" "duracao_s" "cita o campo"; case "$out" in *Traceback*) _fail "traceback exposto";; esac
  python3 - "$d/s.json" <<'PY'
import json, sys
json.dump({"modo": "gerado", "cenas": [{"id": "c1", "prompt": "x"}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(python3 "$ROOT/scripts/storyboard_to_genplan.py" "$d/s.json" 2>&1) && _fail "duração ausente aceita"
  assert_contains "$out" "duracao_s" "cita o campo (ausente)"; case "$out" in *Traceback*) _fail "traceback exposto (ausente)";; esac
  rm -rf "$d"
}

test_storyboard_float_noise_does_not_add_a_second() {
  local d out; d="$(mktemp -d)"
  python3 - "$d/s.json" <<'PY'
import json, sys
json.dump({"modo": "gerado", "cenas": [{"id": "c1", "prompt": "x", "duracao_s": 6.0000001}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(python3 "$ROOT/scripts/storyboard_to_genplan.py" "$d/s.json" 2>/dev/null) || _fail "falhou"
  assert_eq 6 "$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin)['cenas'][0]['duracao_s'])")" "6,0000001 vira 6, não 7"
  rm -rf "$d"
}

test_nan_in_captions_is_refused() {
  local d out; d="$(mktemp -d)"; _gen "$d" false 0 0
  printf '%s' '{"estilo":"padrao","cenas":[{"cena":"c1","legendas":[{"texto":"Oi","inicio_s":NaN,"fim_s":3}]}]}' > "$d/c.json"
  out=$(python3 "$ROOT/scripts/captions_to_transcript.py" "$d/c.json" "$d/g.json" "$d/w/clips-manifest.json" 2>&1) && _fail "NaN aceito"
  assert_contains "$out" "inicio_s" "cita o campo"; case "$out" in *Traceback*) _fail "traceback exposto";; esac
  rm -rf "$d"
}

test_volume_with_underscore_digits_is_refused() {
  local d out; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "color=c=red:size=320x240:rate=25:duration=2" -c:v libx264 -pix_fmt yuv420p -an "$d/v.mp4" </dev/null
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=2" "$d/m.wav" </dev/null
  out=$(bash "$ROOT/scripts/add-soundtrack.sh" "$d/v.mp4" "$d/m.wav" "$d/o.mp4" --volume-db "-1_8" --check-only 2>&1) && _fail "-1_8 aceito"
  assert_contains "$out" "volume inválido" "mensagem"
  rm -rf "$d"
}

test_srt_path_ignores_dots_in_directories_and_missing_extension() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/pasta.v2"
  ffmpeg -v error -y -f lavfi -i "color=c=red:size=320x240:rate=25:duration=3" -c:v libx264 -pix_fmt yuv420p -an "$d/v.mp4" </dev/null
  printf '%s' '{"idioma":"pt","segmentos":[{"inicio_s":0.2,"fim_s":2,"texto":"Oi"}]}' > "$d/t.json"
  bash "$ROOT/scripts/subtitles.sh" "$d/v.mp4" "$d/t.json" "$d/pasta.v2/saida" --srt-only >/dev/null 2>&1 || _fail "subtitles falhou"
  assert_file_exists "$d/pasta.v2/saida.srt"
  [ ! -e "$d/pasta.srt" ] || _fail "o .srt foi parar fora da pasta de saída"
  rm -rf "$d"
}

test_edit_generated_checks_output_folder_and_gen_plan_early() {
  local d out; d="$(mktemp -d)"; _gen "$d" false 0 0
  bash "$ROOT/scripts/assemble-clips.sh" "$d/g.json" "$d/w/clips-manifest.json" "$d/montado.mp4" >/dev/null 2>&1 || _fail "montagem falhou"
  python3 - "$d/c.json" <<'PY'
import json, sys
json.dump({"estilo": "padrao", "cenas": [{"cena": "c1", "legendas": [{"texto": "Oi"}]}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  out=$(bash "$ROOT/scripts/edit-generated.sh" "$d/montado.mp4" "$d/g.json" "$d/w/clips-manifest.json" "$d/nao/existe/final.mp4" --captions "$d/c.json" 2>&1) && _fail "pasta de saída inexistente aceita"
  assert_contains "$out" "pasta" "mensagem em português sobre a pasta"
  printf '%s' '{"cenas": 5}' > "$d/ruim.json"
  out=$(bash "$ROOT/scripts/edit-generated.sh" "$d/montado.mp4" "$d/ruim.json" "$d/w/clips-manifest.json" "$d/final.mp4" --captions "$d/c.json" 2>&1) && _fail "gen-plan inválido aceito"
  case "$out" in *Traceback*) _fail "traceback exposto";; esac
  assert_contains "$out" "plano" "mensagem sobre o plano"
  rm -rf "$d"
}

test_music_only_force_removes_the_stale_srt() {
  local d; d="$(mktemp -d)"; _gen "$d" false 0 0
  bash "$ROOT/scripts/assemble-clips.sh" "$d/g.json" "$d/w/clips-manifest.json" "$d/montado.mp4" >/dev/null 2>&1 || _fail "montagem falhou"
  python3 - "$d/c.json" <<'PY'
import json, sys
json.dump({"estilo": "padrao", "cenas": [{"cena": "c1", "legendas": [{"texto": "Oi"}]}]}, open(sys.argv[1], "w", encoding="utf-8"))
PY
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=4" "$d/m.wav" </dev/null
  bash "$ROOT/scripts/edit-generated.sh" "$d/montado.mp4" "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" --captions "$d/c.json" >/dev/null 2>&1 || _fail "primeira edição falhou"
  assert_file_exists "$d/final.srt"
  bash "$ROOT/scripts/edit-generated.sh" "$d/montado.mp4" "$d/g.json" "$d/w/clips-manifest.json" "$d/final.mp4" --music "$d/m.wav" --force >/dev/null 2>&1 || _fail "edição só com música falhou"
  [ ! -e "$d/final.srt" ] || _fail "o .srt antigo ficou ao lado de um vídeo sem legendas"
  rm -rf "$d"
}

test_digitally_silent_music_gets_a_clear_message() {
  local d out; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "color=c=red:size=320x240:rate=25:duration=2" -c:v libx264 -pix_fmt yuv420p -an "$d/v.mp4" </dev/null
  ffmpeg -v error -y -f lavfi -i "anullsrc=r=44100:cl=mono" -t 2 "$d/mudo.wav" </dev/null
  out=$(bash "$ROOT/scripts/add-soundtrack.sh" "$d/v.mp4" "$d/mudo.wav" "$d/o.mp4" --check-only 2>&1) && _fail "música silenciosa aceita"
  assert_contains "$out" "silenc" "diz que a música está silenciosa"
  rm -rf "$d"
}
