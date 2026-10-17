#!/usr/bin/env bash
# Testes de scripts/run-gen-variants.sh (vários vídeos finais a partir dos mesmos clipes gerados; custo zero)

_rv() { bash "$ROOT/scripts/run-gen-variants.sh" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
_nstreams() { ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$1" | wc -l | tr -d ' '; }

# _prep <dir> [expressão python sobre p] → g.json (c1 4 s, c2 5 s, c3 6 s), clipes reais, manifesto, v.json (A: c1,c2,c3; B: c3,c1 + música) e m.wav
_prep() {
  local d="$1" id cor dur
  mkdir -p "$d/w/clips"
  python3 - "$d" "${2:-pass}" <<'PY'
import json, os, sys
d = sys.argv[1]
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "a", "duracao_s": 4}, {"id": "c2", "prompt": "b", "duracao_s": 5}, {"id": "c3", "prompt": "c", "duracao_s": 6}]},
          open(os.path.join(d, "g.json"), "w", encoding="utf-8"))
p = {"quantidade": 2, "variantes": [
    {"id": "A", "cenas": ["c1", "c2", "c3"], "aprovada": True, "achados": ["pergunta no início"],
     "legendas": {"estilo": "padrao", "cenas": [{"cena": "c1", "legendas": [{"texto": "Sua rotina vive bagunçada?"}]},
                                                  {"cena": "c2", "legendas": [{"texto": "O Clo App organiza tudo", "inicio_s": 0.5, "fim_s": 3}]}]}},
    {"id": "B", "cenas": ["c3", "c1"], "aprovada": True, "achados": ["resultado primeiro"], "musica": "m.wav", "volume_db": -12,
     "legendas": {"estilo": "destaque", "cenas": [{"cena": "c3", "legendas": [{"texto": "Tudo em um lugar só"}]}]}}]}
exec(sys.argv[2])
json.dump(p, open(os.path.join(d, "v.json"), "w", encoding="utf-8"), ensure_ascii=False)
PY
  for pair in "c1 red 4" "c2 green 5" "c3 blue 6"; do
    read -r id cor dur <<EOP
$pair
EOP
    ffmpeg -v error -y -f lavfi -i "color=c=$cor:size=480x854:rate=25:duration=$dur" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/$id.mp4" </dev/null
    python3 "$ROOT/scripts/clips_manifest.py" add "$d/w/clips-manifest.json" "$id" "clips/$id.mp4" 1 "$(python3 "$ROOT/scripts/genplan_info.py" "$d/g.json" key "$id")" fake >/dev/null
  done
  ffmpeg -v error -y -f lavfi -i "sine=frequency=220:duration=4" "$d/m.wav" </dev/null
}
_go() { local d="$1"; shift; _rv "$d/g.json" "$d/w/clips-manifest.json" "$d/out" --variants "$d/v.json" "$@"; }

test_generates_each_approved_variant_with_its_own_order_and_captions() {
  local d; d="$(mktemp -d)"; _prep "$d"
  _go "$d" >/dev/null 2>&1 || _fail "run-gen-variants falhou"
  assert_file_exists "$d/out/final-A.mp4"; assert_file_exists "$d/out/final-B.mp4"
  assert_file_exists "$d/out/final-A.srt"; assert_file_exists "$d/out/final-B.srt"
  assert_near 15 "$(_dur "$d/out/final-A.mp4")" 0.4 "A tem os 3 clipes"
  assert_near 10 "$(_dur "$d/out/final-B.mp4")" 0.4 "B tem só c3 e c1"
  assert_contains "$(cat "$d/out/final-A.srt")" "00:00:04,500 --> 00:00:07,000" "A: c2 começa em 4 + 0,5"
  assert_contains "$(cat "$d/out/final-B.srt")" "00:00:00,200 --> 00:00:05,800" "B: a primeira cena (c3, 6 s) abre o vídeo"
  assert_eq 0 "$(_nstreams "$d/out/final-A.mp4")" "A sem trilha segue mudo"
  assert_eq 1 "$(_nstreams "$d/out/final-B.mp4")" "B tem a trilha própria"
  rm -rf "$d"
}

test_unapproved_variants_are_skipped_and_none_approved_dies() {
  local d out; d="$(mktemp -d)"; _prep "$d" "p['variantes'][1]['aprovada']=False"
  _go "$d" >/dev/null 2>&1 || _fail "falhou"
  assert_file_exists "$d/out/final-A.mp4"
  [ ! -e "$d/out/final-B.mp4" ] || _fail "variante não aprovada foi gerada"
  rm -rf "$d"; d="$(mktemp -d)"; _prep "$d" "p['variantes'][0]['aprovada']=False; p['variantes'][1]['aprovada']=False"
  out=$(_go "$d" 2>&1) && _fail "nenhuma aprovada deveria falhar"; assert_contains "$out" "aprovad" "mensagem"
  rm -rf "$d"
}

test_batch_is_validated_before_producing_anything() {
  local d out; d="$(mktemp -d)"
  _prep "$d" "p['variantes'][1]['legendas']['cenas'][0]['legendas'][0]['texto']='x'*90"
  out=$(_go "$d" 2>&1) && _fail "legenda grande deveria recusar o lote"
  assert_contains "$out" "B" "cita a variante"
  [ ! -e "$d/out/final-A.mp4" ] || _fail "A foi gerada apesar de B inválida"
  rm -rf "$d"; d="$(mktemp -d)"; _prep "$d" "p['variantes'][1]['musica']='nao-existe.wav'"
  out=$(_go "$d" 2>&1) && _fail "música inexistente deveria recusar o lote"
  [ ! -e "$d/out/final-A.mp4" ] || _fail "A foi gerada apesar da música de B ser inválida"
  rm -rf "$d"
}

test_tampered_clip_is_refused_without_output() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  ffmpeg -v error -y -f lavfi -i "color=c=white:size=480x854:rate=25:duration=4" -c:v libx264 -pix_fmt yuv420p -an "$d/w/clips/c1.mp4" </dev/null
  out=$(_go "$d" 2>&1) && _fail "clipe alterado deveria ser recusado"
  assert_contains "$out" "manifesto" "mensagem"
  [ ! -e "$d/out/final-A.mp4" ] || _fail "gerou com clipe alterado"
  rm -rf "$d"
}

test_existing_outputs_need_force_and_rerun_is_safe() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  _go "$d" >/dev/null 2>&1 || _fail "primeira execução falhou"
  out=$(_go "$d" 2>&1) && _fail "reexecução sem --force deveria recusar"; assert_contains "$out" "--force" "pede --force"
  _go "$d" --force >/dev/null 2>&1 || _fail "--force falhou"
  assert_file_exists "$d/out/final-A.mp4"
  rm -rf "$d"
}

test_no_partial_files_or_credit_use() {
  local d; d="$(mktemp -d)"; _prep "$d"
  _go "$d" >/dev/null 2>&1 || _fail "falhou"
  [ -z "$(find "$d/out" -name '.*partial*' | head -1)" ] || _fail "sobrou arquivo parcial"
  [ ! -e "$d/budget.json" ] || _fail "não deveria tocar em orçamento"
  rm -rf "$d"
}

test_works_from_a_relative_directory_and_requires_arguments() {
  local d out; d="$(mktemp -d)"; _prep "$d"
  (cd "$d" && bash "$ROOT/scripts/run-gen-variants.sh" g.json w/clips-manifest.json out --variants v.json) >/dev/null 2>&1 || _fail "caminhos relativos falharam"
  assert_file_exists "$d/out/final-B.mp4"
  out=$(_rv 2>&1) && _fail "sem argumentos deveria falhar"; assert_contains "$out" "uso" "uso"
  out=$(_rv "$d/g.json" "$d/w/clips-manifest.json" "$d/o2" 2>&1) && _fail "sem --variants deveria falhar"; assert_contains "$out" "--variants" "exige o plano"
  rm -rf "$d"
}

test_abspath_keeps_windows_drive_paths() {
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/common.sh"
  assert_eq 'C:\Users\x\a.mp4' "$(abspath 'C:\Users\x\a.mp4')" "caminho com letra de unidade já é absoluto"
  assert_eq 'D:/x/a.mp4' "$(abspath 'D:/x/a.mp4')" "com barra normal"
}
