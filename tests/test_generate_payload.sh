#!/usr/bin/env bash
# Modo mcp-agent de scripts/generate-clips.sh: o script monta o payload e registra; o AGENTE faz a chamada ao Higgsfield

_gc() { bash "$ROOT/scripts/generate-clips.sh" "$@"; }
_bg() { python3 "$ROOT/scripts/budget.py" "$@"; }
_dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
UUID="3f2b8c1e-5a4d-4e6f-9a7b-1c2d3e4f5a6b"

_prep() { # <dir> <teto>
  mkdir -p "$1"
  python3 - "$1/g.json" <<'PY'
import json, sys
json.dump({"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": "480p", "audio": False,
           "cenas": [{"id": "c1", "prompt": "pessoa olhando o celular", "duracao_s": 4},
                     {"id": "c2", "prompt": "tela do app organizando tarefas", "duracao_s": 5}]},
          open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  _bg init "$1/b.json" "$2" >/dev/null
}
_pl() { local d="$1"; shift; _gc "$d/g.json" "$d/w" --generator mcp-agent "$@"; }
# emite o payload de geração (marca a cena como "emitida"); o register exige isso
_emit() { _pl "$1" --stage payload --scene "$2" --budget "$1/b.json" >/dev/null 2>&1; }
# registra a cotação que o agente obteve com get_cost
_rq() { _pl "$1" --stage register-quote --scene "$2" --custo "$3" --budget "$1/b.json"; }
# clipe de teste com a duração dada
_clip() { ffmpeg -v error -y -f lavfi -i "testsrc2=size=480x854:rate=25:duration=$2" -c:v libx264 -pix_fmt yuv420p -an "$1" </dev/null; }

test_cost_only_payload_has_exactly_the_expected_fields() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100
  out=$(_pl "$d" --stage payload --scene c1 --cost-only) || _fail "payload falhou"
  printf '%s' "$out" > "$d/p.json"
  assert_eq "seedance_2_5" "$(json_get "$d/p.json" "d['params']['model']")" "modelo"
  assert_eq "pessoa olhando o celular" "$(json_get "$d/p.json" "d['params']['prompt']")" "prompt"
  assert_eq "9:16" "$(json_get "$d/p.json" "d['params']['aspect_ratio']")" "aspecto"
  assert_eq 4 "$(json_get "$d/p.json" "d['params']['duration']")" "duração inteira"
  assert_eq "480p" "$(json_get "$d/p.json" "d['params']['resolution']")" "resolução"
  assert_eq "False" "$(json_get "$d/p.json" "d['params']['generate_audio']")" "áudio"
  assert_eq 1 "$(json_get "$d/p.json" "d['params']['count']")" "uma geração por chamada"
  assert_eq "True" "$(json_get "$d/p.json" "d['params']['get_cost']")" "só cotar"
  assert_eq "['aspect_ratio', 'count', 'duration', 'generate_audio', 'get_cost', 'model', 'prompt', 'resolution']" \
    "$(json_get "$d/p.json" "sorted(d['params'])")" "nenhum campo extra"
  case "$out" in *use_unlim*|*use_free_gens*|*preset_session_id*|*medias*|*folder_id*) _fail "campo proibido no payload: $out" ;; esac
  rm -rf "$d"
}

test_generation_payload_needs_a_confirmed_quote() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100
  out=$(_pl "$d" --stage payload --scene c1 2>&1) && _fail "payload de geração sem --budget"
  assert_contains "$out" "budget" "mensagem"
  out=$(_pl "$d" --stage payload --scene c1 --budget "$d/b.json" 2>&1) && _fail "payload de geração sem cotação"
  assert_contains "$out" "cotação" "mensagem"
  _rq "$d" c1 4 >/dev/null; _rq "$d" c2 5 >/dev/null
  out=$(_pl "$d" --stage payload --scene c1 --budget "$d/b.json" 2>&1) && _fail "payload de geração sem confirmação"
  assert_contains "$out" "confirm" "mensagem"
  _bg confirm "$d/b.json" 9 >/dev/null 2>&1 || _fail "confirm falhou"
  out=$(_pl "$d" --stage payload --scene c1 --budget "$d/b.json") || _fail "payload de geração confirmado falhou"
  printf '%s' "$out" > "$d/p.json"
  assert_eq "False" "$(json_get "$d/p.json" "d['params']['get_cost']")" "agora gera de verdade"
  rm -rf "$d"
}

test_register_quote_goes_to_the_budget() {
  local d; d="$(mktemp -d)"; _prep "$d" 100
  _rq "$d" c1 4 >/dev/null || _fail "register-quote falhou"
  assert_contains "$(_bg status "$d/b.json")" "total cotado: 4" "cotação registrada"
  _rq "$d" c1 abc >/dev/null 2>&1 && _fail "custo inválido aceito"
  _rq "$d" c1 -1 >/dev/null 2>&1 && _fail "custo negativo aceito"
  _rq "$d" nao-existe 4 >/dev/null 2>&1 && _fail "cena inexistente aceita"
  rm -rf "$d"
}

test_register_valid_clip_spends_and_updates_the_manifest() {
  local d; d="$(mktemp -d)"; _prep "$d" 100
  _rq "$d" c1 4 >/dev/null; _rq "$d" c2 5 >/dev/null; _bg confirm "$d/b.json" 9 >/dev/null 2>&1
  _clip "$d/baixado.mp4" 4
  _emit "$d" c1
  _pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/baixado.mp4" --budget "$d/b.json" >/dev/null 2>&1 || _fail "register falhou"
  assert_file_exists "$d/w/clips/c1.mp4"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 4" "gasto"
  assert_eq "mcp-agent" "$(json_get "$d/w/clips-manifest.json" "d['clips']['c1']['origem']")" "origem"
  assert_eq "$UUID" "$(json_get "$d/w/clips-manifest.json" "d['clips']['c1']['job_id']")" "job_id"
  rm -rf "$d"
}

test_register_without_confirmation_is_refused() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100; _rq "$d" c1 4 >/dev/null
  _clip "$d/baixado.mp4" 4
  _emit "$d" c1
  out=$(_pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/baixado.mp4" --budget "$d/b.json" 2>&1) && _fail "register sem confirmação aceito"
  assert_contains "$out" "confirm" "mensagem"
  [ ! -e "$d/w/clips/c1.mp4" ] || _fail "não deveria copiar o clipe"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto"
  rm -rf "$d"
}

test_register_rejects_invalid_files_job_ids_and_short_clips() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100
  _rq "$d" c1 4 >/dev/null; _rq "$d" c2 5 >/dev/null; _bg confirm "$d/b.json" 9 >/dev/null 2>&1
  echo "isto não é um vídeo" > "$d/falso.mp4"
  out=$(_pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/falso.mp4" --budget "$d/b.json" 2>&1) && _fail "arquivo inválido aceito"
  assert_contains "$out" "vídeo" "mensagem"
  _clip "$d/curto.mp4" 1
  out=$(_pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/curto.mp4" --budget "$d/b.json" 2>&1) && _fail "clipe curto demais aceito"
  assert_contains "$out" "duração" "mensagem"
  _clip "$d/ok.mp4" 4
  _pl "$d" --stage register --scene c1 --job-id "nao-e-uuid" --custo 4 --arquivo "$d/ok.mp4" --budget "$d/b.json" >/dev/null 2>&1 && _fail "job-id inválido aceito"
  _pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/nao-existe.mp4" --budget "$d/b.json" >/dev/null 2>&1 && _fail "arquivo inexistente aceito"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto nas recusas"
  [ ! -e "$d/w/clips/c1.mp4" ] || _fail "nenhum clipe deveria ter sido copiado"
  rm -rf "$d"
}

test_register_over_quote_records_the_overrun() {
  local d rc; d="$(mktemp -d)"; _prep "$d" 100
  _rq "$d" c1 4 >/dev/null; _bg confirm "$d/b.json" 4 >/dev/null 2>&1; _clip "$d/baixado.mp4" 4; _emit "$d" c1
  _pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 9 --arquivo "$d/baixado.mp4" --budget "$d/b.json" >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || _fail "estouro deveria sair com código diferente de zero"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 9" "gasto efetivo registrado"
  assert_file_exists "$d/w/clips/c1.mp4"
  assert_eq 9 "$(json_get "$d/w/clips-manifest.json" "int(d['clips']['c1']['custo'])")" "manifesto com o custo efetivo"
  rm -rf "$d"
}

test_register_twice_or_over_an_existing_clip_is_refused() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100
  _rq "$d" c1 4 >/dev/null; _bg confirm "$d/b.json" 4 >/dev/null 2>&1; _clip "$d/baixado.mp4" 4; _emit "$d" c1
  mkdir -p "$d/w/clips"; echo existente > "$d/w/clips/c1.mp4"
  out=$(_pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/baixado.mp4" --budget "$d/b.json" 2>&1) && _fail "sobrescreveu clipe existente"
  assert_contains "$out" "--force" "mensagem"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 0" "nada gasto antes da recusa"
  rm -f "$d/w/clips/c1.mp4"
  _pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/baixado.mp4" --budget "$d/b.json" >/dev/null 2>&1 || _fail "primeiro registro falhou"
  _pl "$d" --stage register --scene c1 --job-id "$UUID" --custo 4 --arquivo "$d/baixado.mp4" --budget "$d/b.json" --force >/dev/null 2>&1 && _fail "segundo registro da mesma cena paga aceito"
  assert_contains "$(_bg status "$d/b.json")" "gasto: 4" "cobrada uma vez"
  rm -rf "$d"
}

test_agent_mode_refuses_the_script_driven_stages() {
  local d out; d="$(mktemp -d)"; _prep "$d" 100
  out=$(_pl "$d" --stage run --budget "$d/b.json" 2>&1) && _fail "run não existe no modo mcp-agent"
  assert_contains "$out" "payload" "orienta o fluxo do agente"
  out=$(_gc "$d/g.json" "$d/w" --generator fake --stage payload --scene c1 2>&1) && _fail "payload não existe no gerador fake"
  rm -rf "$d"
}
