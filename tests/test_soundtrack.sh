#!/usr/bin/env bash
# Testes de scripts/add-soundtrack.sh

_st() { bash "$ROOT/scripts/add-soundtrack.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
_nstreams() { ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$1" | wc -l | tr -d ' '; }

_lufs() { # integrado, em LUFS
  ffmpeg -hide_banner -nostats -i "$1" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 </dev/null \
    | python3 -c "
import sys, json, re
print(json.loads(re.search(r'\{[^{}]*\"input_i\"[^{}]*\}', sys.stdin.read(), re.S).group(0))['input_i'])"
}
_mean_db() { # nível médio (dB) de um trecho: arquivo início duração
  ffmpeg -hide_banner -nostats -ss "$2" -t "$3" -i "$1" -vn -af volumedetect -f null - 2>&1 </dev/null | sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p' | head -1
}

# _mk <dir> → video mudo de 6 s (mudo.mp4), com áudio (com-audio.mp4), músicas curta/longa, silenciosa e só-vídeo
_mk() {
  local d="$1"
  mkdir -p "$d"
  ffmpeg -v error -y -f lavfi -i "testsrc2=size=480x854:rate=25:duration=6" -c:v libx264 -pix_fmt yuv420p -an "$d/mudo.mp4" </dev/null
  ffmpeg -v error -y -f lavfi -i "testsrc2=size=480x854:rate=25:duration=6" -f lavfi -i "sine=frequency=440:duration=6" \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$d/com-audio.mp4" </dev/null
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=3" "$d/curta.wav" </dev/null
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=20" "$d/longa.wav" </dev/null
  ffmpeg -v error -y -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 5 "$d/silenciosa.wav" </dev/null
}

test_short_music_is_looped_to_the_video_length() {
  local d; d="$(mktemp -d)"; _mk "$d"
  _st "$d/mudo.mp4" "$d/curta.wav" "$d/o.mp4" >/dev/null 2>&1 || _fail "add-soundtrack falhou"
  assert_near 6 "$(_dur "$d/o.mp4")" 0.2 "duração do vídeo"
  assert_eq 1 "$(_nstreams "$d/o.mp4")" "uma faixa de áudio"
  assert_near -14 "$(_lufs "$d/o.mp4")" 1.5 "loudness"
  assert_eq "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of csv=p=0 "$d/mudo.mp4")" \
            "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of csv=p=0 "$d/o.mp4")" "vídeo preservado"
  rm -rf "$d"
}

test_long_music_is_trimmed_with_a_fade_out() {
  local d meio fim; d="$(mktemp -d)"; _mk "$d"
  _st "$d/mudo.mp4" "$d/longa.wav" "$d/o.mp4" >/dev/null 2>&1 || _fail "add-soundtrack falhou"
  assert_near 6 "$(_dur "$d/o.mp4")" 0.2 "cortada na duração do vídeo"
  meio="$(_mean_db "$d/o.mp4" 2 1)"; fim="$(_mean_db "$d/o.mp4" 5.5 0.5)"
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) - float(sys.argv[2]) >= 6 else 1)" "$meio" "$fim" \
    || _fail "o fade-out deveria baixar o nível dos últimos 0,5 s em ao menos 6 dB (meio $meio dB, fim $fim dB)"
  rm -rf "$d"
}

test_music_goes_under_the_existing_audio() {
  local d; d="$(mktemp -d)"; _mk "$d"
  _st "$d/com-audio.mp4" "$d/curta.wav" "$d/o.mp4" >/dev/null 2>&1 || _fail "add-soundtrack falhou"
  assert_eq 1 "$(_nstreams "$d/o.mp4")" "uma faixa de áudio na saída"
  assert_near 6 "$(_dur "$d/o.mp4")" 0.2 "duração"
  assert_near -14 "$(_lufs "$d/o.mp4")" 1.5 "loudness"
  rm -rf "$d"
}

test_volume_must_be_between_minus_40_and_0() {
  local d v out; d="$(mktemp -d)"; _mk "$d"
  for v in 5 -50 abc ""; do
    out=$(_st "$d/mudo.mp4" "$d/curta.wav" "$d/o.mp4" --volume-db "$v" 2>&1) && _fail "volume inválido aceito: '$v'"
    assert_contains "$out" "volume" "mensagem ('$v')"
  done
  [ ! -e "$d/o.mp4" ] || _fail "não deveria criar saída"
  _st "$d/mudo.mp4" "$d/curta.wav" "$d/o.mp4" --volume-db -10 >/dev/null 2>&1 || _fail "-10 dB deveria ser aceito"
  rm -rf "$d"
}

test_invalid_music_is_refused() {
  local d out; d="$(mktemp -d)"; _mk "$d"
  out=$(_st "$d/mudo.mp4" "$d/nao-existe.wav" "$d/o.mp4" 2>&1) && _fail "música inexistente aceita"; assert_contains "$out" "música" "inexistente"
  echo "isto não é áudio" > "$d/falso.wav"
  out=$(_st "$d/mudo.mp4" "$d/falso.wav" "$d/o.mp4" 2>&1) && _fail "arquivo de texto aceito"; assert_contains "$out" "não foi possível ler" "ilegível"
  out=$(_st "$d/mudo.mp4" "$d/mudo.mp4" "$d/o.mp4" 2>&1) && _fail "arquivo sem áudio aceito"; assert_contains "$out" "faixa de áudio" "sem áudio"
  out=$(_st "$d/mudo.mp4" "$d/silenciosa.wav" "$d/o.mp4" 2>&1) && _fail "música silenciosa aceita"; assert_contains "$out" "silenciosa" "silenciosa"
  out=$(_st "$d/falso.wav" "$d/curta.wav" "$d/o.mp4" 2>&1) && _fail "vídeo ilegível aceito"; assert_contains "$out" "vídeo" "vídeo ilegível"
  [ ! -e "$d/o.mp4" ] || _fail "nenhuma recusa deveria criar saída"
  [ -z "$(find "$d" -name '.*partial*')" ] || _fail "sobrou arquivo parcial"
  rm -rf "$d"
}

test_existing_output_needs_force() {
  local d out; d="$(mktemp -d)"; _mk "$d"; echo existente > "$d/o.mp4"
  out=$(_st "$d/mudo.mp4" "$d/curta.wav" "$d/o.mp4" 2>&1) && _fail "sobrescreveu sem --force"
  assert_contains "$out" "--force" "mensagem"
  assert_eq existente "$(cat "$d/o.mp4")" "arquivo intacto"
  _st "$d/mudo.mp4" "$d/curta.wav" "$d/o.mp4" --force >/dev/null 2>&1 || _fail "--force deveria permitir"
  rm -rf "$d"
}

test_relative_paths_and_spaces() {
  local d; d="$(mktemp -d)/pasta com espaço é"; _mk "$d"
  cp "$d/curta.wav" "$d/minha música.wav"
  (cd "$d" && bash "$ROOT/scripts/add-soundtrack.sh" mudo.mp4 "minha música.wav" "saída final.mp4" >/dev/null 2>&1) || _fail "caminhos relativos/espaços falharam"
  assert_file_exists "$d/saída final.mp4"
  rm -rf "$d"
}
