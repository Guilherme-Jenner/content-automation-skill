#!/usr/bin/env bash
# Minors adiados das fases 1/1b (ledger): executar de dentro da pasta, opções sem valor, áudio silencioso

test_scripts_run_from_their_own_directory() {
  local f dir out bad=""
  for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/*/*.sh; do
    case "$f" in */lib/*|*/check-deps.sh) continue ;; esac
    dir="$(dirname "$f")"
    out=$(cd "$dir" && bash "$(basename "$f")" 2>&1 </dev/null) || true
    case "$out" in *"No such file or directory"*|*"Not a directory"*|*"unbound variable"*) bad="$bad ${f#"$ROOT"/}" ;; esac
  done
  [ -z "$bad" ] || _fail "scripts que quebram quando chamados de dentro da própria pasta:$bad"
}

test_options_without_value_give_a_clear_message() {
  local d out; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "testsrc=duration=2:size=320x240:rate=25" -f lavfi -i "sine=frequency=440:duration=2" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$d/v.mp4" </dev/null
  out=$(bash "$ROOT/scripts/transcribe.sh" "$d/v.mp4" "$d/t.json" --lang 2>&1) && _fail "--lang sem valor aceito"
  assert_contains "$out" "--lang" "cita a opção"; case "$out" in *"parameter null"*|*"unbound"*) _fail "mensagem crua do bash";; esac
  out=$(bash "$ROOT/scripts/reframe-9x16.sh" "$d/v.mp4" "$d/r.mp4" --mode 2>&1) && _fail "--mode sem valor aceito"
  assert_contains "$out" "--mode" "cita a opção"; case "$out" in *"parameter null"*|*"unbound"*) _fail "mensagem crua do bash";; esac
  for o in --min-silence --noise --pad; do
    out=$(bash "$ROOT/scripts/silence-detect.sh" "$d/v.mp4" "$d/s.json" "$o" 2>&1) && _fail "$o sem valor aceito"
    assert_contains "$out" "$o" "cita $o"; case "$out" in *"parameter null"*|*"unbound"*) _fail "mensagem crua do bash para $o";; esac
  done
  rm -rf "$d"
}

test_digital_silence_is_refused_with_a_clear_message() {
  local d out; d="$(mktemp -d)"
  ffmpeg -v error -y -f lavfi -i "testsrc=duration=3:size=320x240:rate=25" -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 3 -c:v libx264 -pix_fmt yuv420p -c:a aac "$d/mudo.mp4" </dev/null
  out=$(bash "$ROOT/scripts/normalize-audio.sh" "$d/mudo.mp4" "$d/n.mp4" 2>&1) && _fail "áudio totalmente silencioso deveria ser recusado"
  assert_contains "$out" "silêncio" "explica que o áudio é silêncio"
  [ ! -e "$d/n.mp4" ] || _fail "gerou saída com áudio silencioso"
  rm -rf "$d"
}
